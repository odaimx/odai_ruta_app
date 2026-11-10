import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:odai_ruta/src/almacen.dart';
import 'package:odai_ruta/src/api.dart';
import 'package:odai_ruta/src/base_local.dart';
import 'package:odai_ruta/src/motor.dart';
import 'package:odai_ruta/src/pin.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Un Odoo de mentira con las mismas respuestas que odai_ruta_movil.
class OdooFalso {
  bool conSenal = true;
  String estado = 'activo';
  List<Map<String, Object?>> comandos = [];
  final recibidas = <String, Map>{};
  final llamadas = <String>[];
  Map<String, Object?>? ultimoLatido;
  Map<String, Object?>? ultimaBajada;
  String catalogoMarca = 'm1';
  String versionImagen = '';
  String? cookie;

  late final cliente = MockClient((peticion) async {
    if (!conSenal) throw http.ClientException('sin red');
    final ruta = peticion.url.path;
    if (ruta == '/web/login') {
      return http.Response('', 303, headers: {'set-cookie': 'session_id=abc123; Path=/; HttpOnly'});
    }
    llamadas.add(ruta.split('/').last);
    cookie = peticion.headers['Cookie'];
    final cuerpo = jsonDecode(peticion.body) as Map<String, Object?>;
    final autorizado = peticion.headers['Authorization'] == 'Bearer tok';
    Map<String, Object?> json(Object o, [int s = 200]) => {'_': o, '_s': s};
    Map<String, Object?> r;
    switch (ruta.split('/').last) {
      case 'emparejar':
        r = cuerpo['codigo'] == 'bueno'
            ? json({
                'token': 'tok',
                'dispositivo_id': 7,
                'usuario': {'id': 5, 'nombre': 'Vendedor Uno'},
                'empresa': {'id': 1, 'nombre': 'Odai'},
                'pin': {'sal': '00112233445566778899aabbccddeeff',
                  'hash': pbkdf2Sha256Hex('4821', '00112233445566778899aabbccddeeff', 1000), 'iteraciones': 1000},
              })
            : json({'error': {'codigo': 'datos', 'mensaje': 'El código no es válido.'}}, 400);
      case 'latido':
        ultimoLatido = cuerpo;
        r = !autorizado
            ? json({'error': {'codigo': 'token_invalido', 'mensaje': 'Ya no autorizado'}}, 401)
            : json({
                'servidor': '2026-11-09 18:00:00',
                'estado': estado,
                'trabajar_hasta': estado == 'activo' ? '2026-11-12 18:00:00' : false,
                'comandos': comandos,
                'pin': {'sal': '00112233445566778899aabbccddeeff',
                  'hash': pbkdf2Sha256Hex('4821', '00112233445566778899aabbccddeeff', 1000), 'iteraciones': 1000},
                'licencia': {'nivel': 'ok', 'mensaje': ''},
                'version_minima': '1.0.0',
              });
      case 'subir':
        final resultados = <Map>[];
        for (final op in (cuerpo['operaciones'] as List).cast<Map>()) {
          final uuid = op['uuid'] as String;
          if (recibidas.containsKey(uuid)) {
            resultados.add({...recibidas[uuid]!, 'estado': 'repetido', 'estado_original': recibidas[uuid]!['estado']});
            continue;
          }
          final datos = op['datos'] as Map;
          final res = datos['falla'] == 'regla'
              ? {'uuid': uuid, 'estado': 'rechazado', 'mensaje': 'Sin crédito', 'resultado': {}}
              : datos['falla'] == 'tecnica'
                  ? {'uuid': uuid, 'estado': 'error', 'mensaje': 'Falla', 'resultado': {}}
                  : {'uuid': uuid, 'estado': 'hecho', 'mensaje': '', 'resultado': {'id': 1}};
          if (res['estado'] != 'error') recibidas[uuid] = res;
          resultados.add(res);
        }
        r = json({'resultados': resultados});
      case 'bajar':
        ultimaBajada = cuerpo;
        final desde = (cuerpo['desde'] as Map?) ?? {};
        r = json({
          'jornadas': [
            {'jornada': {'id': 3, 'ruta': 'Ruta Norte', 'fecha': '2026-11-10'}, 'visitas': [],
              'config': {'imagenes': versionImagen.isNotEmpty}}
          ],
          'catalogo': desde['catalogo'] == catalogoMarca
              ? null
              : [{'id': 1, 'name': 'Refresco', 'imagen': versionImagen}, {'id': 2, 'name': 'Agua', 'imagen': ''}],
          'listas': {},
          'iva': {},
          'visita_lista': {},
          'facturas': {},
          'motivos': [],
          'marcas': {'catalogo': catalogoMarca, 'precios': 'p1'},
        });
      case 'pin':
        r = json({'pin': {'sal': cuerpo['sal'], 'hash': cuerpo['hash'], 'iteraciones': 1000, 'temporal': false}});
      case 'solicitar_pin':
        r = json({'mensaje': 'Aviso enviado'});
      case 'imagenes':
        r = json({
          'imagenes': {
            for (final id in (cuerpo['ids'] as List).cast<int>())
              if (id == 1) '$id': {'b64': base64Encode([1, 2, 3]), 'tipo': 'image/png', 'version': versionImagen}
          }
        });
      default:
        r = json({}, 404);
    }
    return http.Response(jsonEncode(r['_']), r['_s'] as int, headers: {'content-type': 'application/json'});
  });
}

void main() {
  sqfliteFfiInit();
  late OdooFalso odoo;
  late AlmacenEnMemoria almacen;
  late DateTime ahora;

  Motor nuevoMotor() => Motor(
        almacen: almacen,
        abrirBase: (_) async {
          final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
              options: OpenDatabaseOptions(version: 1, onCreate: BaseLocal.crearTablas, singleInstance: false));
          return BaseLocal(db);
        },
        crearApi: (url, db, token) => Api(url: url, db: db, token: token, cliente: odoo.cliente),
        reloj: () => ahora,
      );

  const qr = '{"url": "https://demo.odai.lat/", "db": "pruebas_ruta", "codigo": "bueno"}';

  setUp(() {
    odoo = OdooFalso();
    almacen = AlmacenEnMemoria();
    ahora = DateTime.utc(2026, 11, 9, 18);
  });

  test('QR exige https y el código bueno', () async {
    final motor = nuevoMotor();
    await motor.iniciar();
    expect(motor.emparejado, isFalse);
    expect(DatosQr.leer('{"url": "http://x.com/", "db": "", "codigo": "c"}').url, 'https://x.com',
        reason: 'Fuera de desarrollo, http:// se cambia a https://');
    expect(() => motor.emparejar('{"url": "ftp://x.com", "db": "", "codigo": "bueno"}'), throwsA(isA<ApiError>()));
    expect(() => motor.emparejar('hola'), throwsA(isA<ApiError>()));
    await expectLater(motor.emparejar(qr.replaceFirst('bueno', 'malo')), throwsA(isA<ApiError>()));
    expect(motor.emparejado, isFalse);
  });

  test('empareja, elige la base con la cookie, baja y desbloquea con PIN', () async {
    final motor = nuevoMotor();
    await motor.iniciar();
    await motor.emparejar(qr);
    await motor.sincronizar();
    expect(motor.emparejado, isTrue);
    expect(almacen.datos[Claves.token], 'tok');
    expect(odoo.cookie, 'session_id=abc123');
    expect(motor.nombreVendedor, 'Vendedor Uno');
    expect(motor.puedeVender, isTrue);
    expect((await motor.dato('jornadas')) as List, hasLength(1));
    expect(await motor.desbloquear('1111'), isFalse);
    expect(motor.intentosPin, 1);
    expect(await motor.desbloquear('4821'), isTrue);
    // Bajada incremental: manda la marca y conserva el catálogo que ya tenía
    await motor.sincronizar();
    expect((odoo.ultimaBajada!['desde'] as Map)['catalogo'], 'm1');
    expect((await motor.dato('catalogo')) as List, hasLength(2));
  });

  test('cinco PIN equivocados bloquean hasta tener señal', () async {
    final motor = nuevoMotor();
    await motor.iniciar();
    await motor.emparejar(qr);
    await motor.sincronizar();
    for (var i = 0; i < maxIntentosPin; i++) {
      await motor.desbloquear('0000');
    }
    expect(motor.bloqueoPin, isTrue);
    expect(await motor.desbloquear('4821'), isFalse);
    await motor.sincronizar();
    expect(motor.bloqueoPin, isFalse);
    expect(await motor.desbloquear('4821'), isTrue);
  });

  test('sin señal la cola guarda, y al volver sube sin duplicar', () async {
    final motor = nuevoMotor();
    await motor.iniciar();
    await motor.emparejar(qr);
    await motor.sincronizar();
    odoo.conSenal = false;
    final a = await motor.registrar('pedido', {'visita_id': 1});
    await motor.registrar('pedido', {'visita_id': 2, 'falla': 'regla'});
    await motor.registrar('cobro', {'visita_id': 2, 'falla': 'tecnica'});
    await motor.sincronizar();
    expect(motor.pendientes, 3);
    expect(motor.ultimoError, contains('Sin señal'));
    odoo.conSenal = true;
    await motor.sincronizar();
    expect(odoo.recibidas.keys, contains(a));
    expect((await motor.cola!.buscar(a))!.estado, EstadoCola.hecho);
    final revisar = await motor.cola!.porRevisar();
    expect(revisar.map((o) => o.mensaje), ['Sin crédito']);
    expect(motor.pendientes, 1, reason: 'La falla técnica se reintenta después');
    // Cada operación lleva su uuid también dentro de los datos (Odoo lo usa para no duplicar)
    expect((await motor.cola!.buscar(a))!.datos['uuid'], a);
    // Tras cinco fallas técnicas queda para la oficina
    for (var i = 0; i < 5; i++) {
      await motor.sincronizar();
    }
    expect(motor.pendientes, 0);
    expect((await motor.cola!.porRevisar()).length, 2);
  });

  test('sin conectarse más allá del permiso no vende; reloj atrasado tampoco', () async {
    final motor = nuevoMotor();
    await motor.iniciar();
    await motor.emparejar(qr);
    await motor.sincronizar();
    expect(motor.puedeVender, isTrue);
    ahora = DateTime.utc(2026, 11, 13);
    expect(motor.puedeVender, isFalse);
    expect(() => motor.registrar('pedido', {}), throwsA(isA<ApiError>()));
    // La visita sin venta sí se guarda (no vende)
    await motor.registrar('sin_venta', {'visita_id': 1});
    ahora = DateTime.utc(2026, 11, 1);
    expect(motor.relojAtrasado, isTrue);
    expect(motor.puedeVender, isFalse);
  });

  test('comandos del supervisor: bloquear, desbloquear y borrar', () async {
    final motor = nuevoMotor();
    await motor.iniciar();
    await motor.emparejar(qr);
    await motor.sincronizar();
    odoo.comandos = [{'id': 1, 'tipo': 'bloquear'}];
    odoo.estado = 'bloqueado';
    await motor.sincronizar();
    expect(motor.bloqueado, isTrue);
    expect(motor.puedeVender, isFalse);
    odoo.comandos = [{'id': 2, 'tipo': 'desbloquear'}];
    odoo.estado = 'activo';
    await motor.sincronizar();
    expect(odoo.ultimoLatido!['comandos_hechos'], [1]);
    expect(motor.bloqueado, isFalse);
    // Borrar: antes sube lo pendiente
    odoo.conSenal = false;
    final uuid = await motor.registrar('pedido', {'visita_id': 1});
    odoo.conSenal = true;
    odoo.comandos = [{'id': 3, 'tipo': 'borrar'}];
    await motor.sincronizar();
    expect(odoo.recibidas.keys, contains(uuid));
    expect(motor.emparejado, isFalse);
    expect(almacen.datos.containsKey(Claves.token), isFalse);
    expect(almacen.datos.containsKey(Claves.idInstalacion), isTrue);
  });

  test('token revocado: avisa y no vende', () async {
    final motor = nuevoMotor();
    await motor.iniciar();
    await motor.emparejar(qr);
    await motor.sincronizar();
    motor.api!.token = 'otro';
    await motor.sincronizar();
    expect(motor.noAutorizado, isTrue);
    expect(motor.puedeVender, isFalse);
  });

  test('fotos de productos: bajan una vez y se vuelven a pedir solo si cambian', () async {
    odoo.versionImagen = 'v1';
    final motor = nuevoMotor();
    await motor.iniciar();
    await motor.emparejar(qr);
    await motor.sincronizar();
    expect(await motor.imagen(1), [1, 2, 3]);
    expect(await motor.imagen(2), isNull);
    expect(odoo.llamadas.where((l) => l == 'imagenes'), hasLength(1));
    await motor.sincronizar();
    expect(odoo.llamadas.where((l) => l == 'imagenes'), hasLength(1), reason: 'misma versión: no se pide de nuevo');
    odoo
      ..versionImagen = 'v2'
      ..catalogoMarca = 'm2';
    await motor.sincronizar();
    expect(odoo.llamadas.where((l) => l == 'imagenes'), hasLength(2));
  });

  test('PIN temporal: obliga a poner uno propio, que se cifra en el celular', () async {
    final motor = nuevoMotor();
    await motor.iniciar();
    await motor.emparejar(qr);
    await motor.sincronizar();
    expect(await motor.solicitarPin(), 'Aviso enviado');
    expect(await motor.desbloquear('4821'), isTrue);
    expect(() => motor.cambiarPin('12'), throwsA(isA<ApiError>()));
    await motor.cambiarPin('9137');
    expect(motor.pinTemporal, isFalse);
    motor.bloquearPantalla();
    expect(await motor.desbloquear('4821'), isFalse);
    expect(await motor.desbloquear('9137'), isTrue);
    odoo.conSenal = false;
    await expectLater(motor.cambiarPin('2468'), throwsA(isA<ApiError>()));
  });
}
