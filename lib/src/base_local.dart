import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite_sqlcipher/sqflite.dart' as cipher;
import 'package:sqflite_common/sqlite_api.dart';
import 'package:uuid/uuid.dart';

const _nombre = 'odai_ruta.db';
const _version = 1;

/// Estados de una operación en la cola.
abstract final class EstadoCola {
  /// Espera subir (o se reintenta tras una falla técnica).
  static const pendiente = 'pendiente';

  /// Odoo la aceptó.
  static const hecho = 'hecho';

  /// Regla de negocio (crédito, existencia...): el vendedor debe verla.
  static const rechazado = 'rechazado';

  /// Falla técnica que se repitió [Cola.maxIntentos] veces: queda para la oficina.
  static const error = 'error';
}

/// Base local cifrada (SQLCipher). Guarda lo que bajó del servidor y la cola de lo que hace el vendedor.
class BaseLocal {
  BaseLocal(this.db);

  final Database db;

  static Future<BaseLocal> abrir(String llave) async {
    final ruta = p.join(await cipher.getDatabasesPath(), _nombre);
    final db = await cipher.openDatabase(ruta, password: llave, version: _version, onCreate: crearTablas);
    return BaseLocal(db);
  }

  /// Borra el archivo de la base (comando "borrar" del supervisor).
  static Future<void> borrarArchivo() async {
    await cipher.deleteDatabase(p.join(await cipher.getDatabasesPath(), _nombre));
  }

  static Future<void> crearTablas(Database db, int version) async {
    await db.execute('CREATE TABLE datos (clave TEXT PRIMARY KEY, valor TEXT NOT NULL)');
    await db.execute('''
      CREATE TABLE cola (
        orden INTEGER PRIMARY KEY AUTOINCREMENT,
        uuid TEXT NOT NULL UNIQUE,
        tipo TEXT NOT NULL,
        capturado TEXT NOT NULL,
        datos TEXT NOT NULL,
        estado TEXT NOT NULL DEFAULT 'pendiente',
        intentos INTEGER NOT NULL DEFAULT 0,
        mensaje TEXT,
        resultado TEXT,
        resuelto TEXT
      )''');
    await db.execute('CREATE INDEX cola_estado ON cola (estado, orden)');
  }

  // ---------------------------------------------------------------- datos (lo que bajó)

  Future<Object?> leer(String clave) async {
    final filas = await db.query('datos', where: 'clave = ?', whereArgs: [clave], limit: 1);
    return filas.isEmpty ? null : jsonDecode(filas.first['valor'] as String);
  }

  Future<void> escribir(String clave, Object? valor) => db.insert(
      'datos', {'clave': clave, 'valor': jsonEncode(valor)}, conflictAlgorithm: ConflictAlgorithm.replace);

  /// Escribe varias claves en una sola transacción: o queda la bajada completa o no queda nada.
  Future<void> escribirVarios(Map<String, Object?> valores) => db.transaction((txn) async {
        for (final e in valores.entries) {
          await txn.insert('datos', {'clave': e.key, 'valor': jsonEncode(e.value)},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });

  Future<void> borrarDato(String clave) => db.delete('datos', where: 'clave = ?', whereArgs: [clave]);

  Future<void> close() => db.close();
}

/// Una operación del vendedor (pedido, cobro...) que espera subir.
class Operacion {
  Operacion({
    required this.uuid,
    required this.tipo,
    required this.capturado,
    required this.datos,
    this.estado = EstadoCola.pendiente,
    this.intentos = 0,
    this.mensaje,
    this.resultado,
  });

  final String uuid;
  final String tipo;
  final String capturado;
  final Map<String, Object?> datos;
  final String estado;
  final int intentos;
  final String? mensaje;
  final Map<String, Object?>? resultado;

  factory Operacion.desdeFila(Map<String, Object?> fila) => Operacion(
        uuid: fila['uuid'] as String,
        tipo: fila['tipo'] as String,
        capturado: fila['capturado'] as String,
        datos: (jsonDecode(fila['datos'] as String) as Map).cast<String, Object?>(),
        estado: fila['estado'] as String,
        intentos: fila['intentos'] as int,
        mensaje: fila['mensaje'] as String?,
        resultado: fila['resultado'] == null
            ? null
            : (jsonDecode(fila['resultado'] as String) as Map).cast<String, Object?>(),
      );

  /// Como la espera `POST /subir`.
  Map<String, Object?> paraSubir() => {'uuid': uuid, 'tipo': tipo, 'capturado': capturado, 'datos': datos};
}

/// Hora UTC como la entiende Odoo: "2026-11-09 18:00:00".
String horaOdoo(DateTime momento) => momento.toUtc().toIso8601String().substring(0, 19).replaceFirst('T', ' ');

/// La cola: todo lo que hace el vendedor se guarda aquí primero, en el orden en que lo hizo, y sube cuando hay
/// señal. Cada operación lleva un uuid; reenviarla nunca la duplica en Odoo.
class Cola {
  Cola(this.base, {DateTime Function()? reloj}) : _reloj = reloj ?? DateTime.now;

  static const maxIntentos = 5;

  final BaseLocal base;
  final DateTime Function() _reloj;

  Database get _db => base.db;

  /// Guarda una operación. Devuelve su uuid, que también va dentro de `datos` (así lo usa Odoo para no duplicar
  /// pedidos y cobros).
  Future<String> agregar(String tipo, Map<String, Object?> datos, {String? uuid}) async {
    final id = uuid ?? const Uuid().v4();
    final capturado = horaOdoo(_reloj());
    await _db.insert('cola', {
      'uuid': id,
      'tipo': tipo,
      'capturado': capturado,
      // `capturado` también en los datos: Odoo cuenta el día de la visita por la hora en que se capturó.
      'datos': jsonEncode({'capturado': capturado, ...datos, 'uuid': id}),
    });
    return id;
  }

  Future<List<Operacion>> pendientes({int limite = 50}) async {
    final filas = await _db.query('cola',
        where: 'estado = ?', whereArgs: [EstadoCola.pendiente], orderBy: 'orden', limit: limite);
    return filas.map(Operacion.desdeFila).toList();
  }

  Future<int> contarPendientes() async {
    final r = await _db.rawQuery('SELECT COUNT(*) AS n FROM cola WHERE estado = ?', [EstadoCola.pendiente]);
    return (r.first['n'] as int?) ?? 0;
  }

  /// Rechazadas o con error que el vendedor aún no ha visto.
  Future<List<Operacion>> porRevisar() async {
    final filas = await _db.query('cola',
        where: 'estado IN (?, ?) AND resuelto IS NULL',
        whereArgs: [EstadoCola.rechazado, EstadoCola.error],
        orderBy: 'orden');
    return filas.map(Operacion.desdeFila).toList();
  }

  Future<void> marcarVista(String uuid) =>
      _db.update('cola', {'resuelto': horaOdoo(_reloj())}, where: 'uuid = ?', whereArgs: [uuid]);

  Future<Operacion?> buscar(String uuid) async {
    final filas = await _db.query('cola', where: 'uuid = ?', whereArgs: [uuid], limit: 1);
    return filas.isEmpty ? null : Operacion.desdeFila(filas.first);
  }

  /// Aplica la respuesta de `POST /subir`.
  ///
  /// - `hecho` → hecho.
  /// - `repetido` → el estado que tuvo la primera vez (`estado_original`).
  /// - `rechazado` → rechazado, para que el vendedor lo vea.
  /// - `error` → sigue pendiente y suma un intento; tras [maxIntentos] queda en error para la oficina.
  Future<void> aplicarResultados(List<Object?> resultados) async {
    await _db.transaction((txn) async {
      for (final r in resultados.whereType<Map>()) {
        final uuid = r['uuid'];
        if (uuid is! String) continue;
        var estado = r['estado'] as String? ?? EstadoCola.error;
        if (estado == 'repetido') {
          estado = r['estado_original'] as String? ?? EstadoCola.hecho;
        }
        final valores = <String, Object?>{
          'mensaje': r['mensaje'] as String?,
          'resultado': jsonEncode(r['resultado'] ?? {}),
        };
        if (estado == EstadoCola.hecho || estado == EstadoCola.rechazado) {
          valores['estado'] = estado;
          await txn.update('cola', valores, where: 'uuid = ?', whereArgs: [uuid]);
        } else {
          await txn.rawUpdate(
              'UPDATE cola SET intentos = intentos + 1, mensaje = ?, resultado = ?, '
              'estado = CASE WHEN intentos + 1 >= ? THEN ? ELSE estado END WHERE uuid = ?',
              [valores['mensaje'], valores['resultado'], maxIntentos, EstadoCola.error, uuid]);
        }
      }
    });
  }

  /// Borra lo ya hecho de más de [dias] días, para que la base no crezca sin fin.
  Future<int> limpiar({int dias = 15}) => _db.delete('cola',
      where: 'estado = ? AND capturado < ?',
      whereArgs: [EstadoCola.hecho, horaOdoo(_reloj().subtract(Duration(days: dias)))]);
}
