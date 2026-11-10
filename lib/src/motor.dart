import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'almacen.dart';
import 'api.dart';
import 'base_local.dart';
import 'pin.dart';
import 'ruta.dart';
import 'version.dart';

/// Lo que se guarda en la base local sobre el estado del celular (clave `estado`).
const _claveEstado = 'estado';

/// Partes de la bajada que se guardan tal cual. `null` en la respuesta significa "sin cambios".
const partesBajada = ['jornadas', 'catalogo', 'listas', 'iva', 'visita_lista', 'facturas', 'motivos', 'marcas'];

/// Tipos que venden o cobran: necesitan permiso vigente para trabajar sin señal.
const tiposDeVenta = {'pedido', 'anticipo', 'cobro'};

const maxIntentosPin = 5;

/// Cuánto se tolera que el reloj del celular vaya atrás de la hora más alta que ya vio.
const toleranciaReloj = Duration(minutes: 10);

DateTime? leerHoraOdoo(Object? valor) {
  if (valor is! String || valor.isEmpty) return null;
  return DateTime.tryParse('${valor.replaceFirst(' ', 'T')}Z');
}

/// El corazón de la app: emparejamiento, PIN, permiso para trabajar sin señal, comandos del supervisor, cola y
/// sincronización. Las pantallas solo leen su estado y llaman a sus métodos.
class Motor extends ChangeNotifier {
  Motor({
    required this.almacen,
    required this.abrirBase,
    this.borrarBase,
    this.crearApi,
    DateTime Function()? reloj,
    this.permitirHttp = false,
  }) : reloj = reloj ?? DateTime.now;

  final Almacen almacen;

  /// Abre (o crea) la base local cifrada con la llave dada.
  final Future<BaseLocal> Function(String llave) abrirBase;

  /// Borra el archivo de la base local (comando "borrar").
  final Future<void> Function()? borrarBase;

  /// Para pruebas: cómo crear el cliente de la API.
  final Api Function(String url, String db, String? token)? crearApi;

  final DateTime Function() reloj;

  /// Solo en modo desarrollo se permite `http://`.
  final bool permitirHttp;

  BaseLocal? base;
  Cola? cola;
  Api? api;

  // Estado visible
  bool listo = false;
  bool noAutorizado = false;
  bool desbloqueado = false;
  bool sincronizando = false;
  String? ultimoError;
  int pendientes = 0;
  Map<String, Object?> _estado = {};

  bool get emparejado => api?.token != null;

  Map<String, Object?> get sesion => (_estado['sesion'] as Map?)?.cast<String, Object?>() ?? const {};
  String get nombreVendedor => ((sesion['usuario'] as Map?)?['nombre'] as String?) ?? '';
  String get nombreEmpresa => ((sesion['empresa'] as Map?)?['nombre'] as String?) ?? '';
  DatosPin? get pin => DatosPin.desdeJson(_estado['pin']);
  bool get bloqueado => _estado['bloqueado'] == true;
  bool get bloqueoPin => _estado['bloqueo_pin'] == true;
  int get intentosPin => (_estado['intentos_pin'] as int?) ?? 0;
  DateTime? get trabajarHasta => leerHoraOdoo(_estado['trabajar_hasta']);
  DateTime? get ultimaSync => leerHoraOdoo(_estado['ultima_sync']);
  String get nivelLicencia => ((_estado['licencia'] as Map?)?['nivel'] as String?) ?? 'ok';
  String get mensajeLicencia => ((_estado['licencia'] as Map?)?['mensaje'] as String?) ?? '';
  String get versionMinima => (_estado['version_minima'] as String?) ?? '1.0.0';
  /// Versión nueva que subió el supervisor en Odoo: `{id, version, notas, obligatoria}`, o null.
  Map? get actualizacion {
    final a = _estado['actualizacion'];
    return a is Map && compararVersion(appVersion, '${a['version']}') < 0 ? a : null;
  }

  bool get debeActualizar => compararVersion(appVersion, versionMinima) < 0;

  /// El reloj del celular se atrasó respecto de la hora más alta que ya vio (para estirar el permiso).
  bool get relojAtrasado {
    final maxima = leerHoraOdoo(_estado['hora_maxima']);
    return maxima != null && reloj().toUtc().isBefore(maxima.subtract(toleranciaReloj));
  }

  /// Por qué no se puede vender ahora, o `null` si sí se puede.
  String? get motivoNoVender {
    if (bloqueado) {
      return 'El supervisor bloqueó este celular. Lo que capture se queda guardado aquí y se envía a Odoo cuando '
          'lo desbloqueen.';
    }
    if (noAutorizado) return 'Este celular ya no está autorizado. Pida al supervisor un código nuevo.';
    if (debeActualizar) return 'Actualice la app: Odoo pide la versión $versionMinima o mayor.';
    if (nivelLicencia == 'off') return mensajeLicencia.isEmpty ? 'Licencia vencida o no activada.' : mensajeLicencia;
    if (relojAtrasado) return 'La hora del celular está atrasada. Corríjala y conéctese.';
    final hasta = trabajarHasta;
    if (hasta == null || !reloj().toUtc().isBefore(hasta)) {
      return 'Lleva mucho tiempo sin señal. Conéctese para seguir vendiendo (puede consultar, pero no vender).';
    }
    return null;
  }

  bool get puedeVender => motivoNoVender == null;

  DateTime? _ultimaConexion;

  /// Hubo comunicación con Odoo hace poco: lo que se capture ahora se trata como "con señal" (Odoo puede
  /// rechazarlo en el momento); si no, como "sin señal" (ya se le vendió o cobró al cliente: nunca se rechaza
  /// por crédito ni por cobrar de más).
  bool get conSenal {
    final u = _ultimaConexion;
    return u != null && reloj().difference(u) < const Duration(minutes: 2);
  }

  // ---------------------------------------------------------------- inicio y emparejamiento

  Api _nuevaApi(String url, String db, String? token) =>
      crearApi?.call(url, db, token) ?? Api(url: url, db: db, token: token);

  Future<void> iniciar() async {
    final token = await almacen.leer(Claves.token);
    final url = await almacen.leer(Claves.url);
    if (token != null && url != null) {
      api = _nuevaApi(url, await almacen.leer(Claves.db) ?? '', token);
      await _abrir();
    }
    listo = true;
    notifyListeners();
  }

  Future<void> _abrir() async {
    base ??= await abrirBase(await llaveBaseLocal(almacen));
    cola = Cola(base!, reloj: reloj);
    _estado = ((await base!.leer(_claveEstado)) as Map?)?.cast<String, Object?>() ?? {};
    pendientes = await cola!.contarPendientes();
  }

  Future<void> _guardarEstado() async {
    final ahora = horaOdoo(reloj());
    final maxima = _estado['hora_maxima'] as String?;
    if (maxima == null || ahora.compareTo(maxima) > 0) _estado['hora_maxima'] = ahora;
    await base!.escribir(_claveEstado, _estado);
  }

  /// Canjea el QR del supervisor por el token de este celular.
  Future<void> emparejar(String textoQr) async {
    final qr = DatosQr.leer(textoQr, permitirHttp: permitirHttp);
    var instalacion = await almacen.leer(Claves.idInstalacion);
    if (instalacion == null) {
      instalacion = const Uuid().v4();
      await almacen.escribir(Claves.idInstalacion, instalacion);
    }
    final nueva = _nuevaApi(qr.url, qr.db, null);
    final r = await nueva.emparejar(qr.codigo, {
      'modelo': '',
      'sistema': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      'app_version': appVersion,
      'id_instalacion': instalacion,
    });
    final token = r['token'];
    if (token is! String || token.isEmpty) throw ApiError('servidor', 'El servidor no entregó el acceso.');
    await almacen.escribir(Claves.url, qr.url);
    await almacen.escribir(Claves.db, qr.db);
    await almacen.escribir(Claves.token, token);
    nueva.token = token;
    api = nueva;
    await _abrir();
    final usuarioAnterior = (sesion['usuario'] as Map?)?['id'];
    final usuario = (r['usuario'] as Map?)?['id'];
    if (usuarioAnterior != null && usuarioAnterior != usuario) {
      // Otro vendedor: lo bajado del anterior ya no sirve. La cola se conserva; lo que no sea de este vendedor
      // Odoo lo rechaza y queda a la vista.
      for (final parte in partesBajada) {
        await base!.borrarDato(parte);
      }
    }
    _estado
      ..['sesion'] = {'usuario': r['usuario'], 'empresa': r['empresa'], 'dispositivo_id': r['dispositivo_id']}
      ..['pin'] = r['pin']
      ..['bloqueado'] = false
      ..['bloqueo_pin'] = false
      ..['intentos_pin'] = 0;
    noAutorizado = false;
    desbloqueado = pin == null;
    await _guardarEstado();
    notifyListeners();
    unawaited(sincronizar());
  }

  // ---------------------------------------------------------------- PIN

  /// Valida el PIN sin señal. Tras [maxIntentosPin] fallas, la app queda bloqueada hasta tener señal.
  Future<bool> desbloquear(String pinCapturado) async {
    final datos = pin;
    if (datos == null) {
      desbloqueado = true;
      notifyListeners();
      return true;
    }
    if (bloqueoPin) return false;
    if (await verificarPin(pinCapturado, datos)) {
      _estado['intentos_pin'] = 0;
      desbloqueado = true;
    } else {
      final intentos = intentosPin + 1;
      _estado['intentos_pin'] = intentos;
      if (intentos >= maxIntentosPin) _estado['bloqueo_pin'] = true;
    }
    await _guardarEstado();
    notifyListeners();
    return desbloqueado;
  }

  /// El PIN que tiene es temporal (lo puso el supervisor): hay que cambiarlo por uno propio.
  bool get pinTemporal => (_estado['pin'] as Map?)?['temporal'] == true;

  /// El vendedor pone su propio PIN. Se cifra en el celular; Odoo solo recibe la sal y el hash. Necesita señal.
  Future<void> cambiarPin(String nuevo) async {
    if (!RegExp(r'^\d{4,6}$').hasMatch(nuevo)) throw ApiError('datos', 'El PIN debe tener de 4 a 6 números.');
    if (api == null) throw ApiError('datos', 'El celular no está conectado a Odoo.');
    final iteraciones = pin?.iteraciones ?? 120000;
    final sal = nuevaSal();
    final hash = await Isolate.run(() => pbkdf2Sha256Hex(nuevo, sal, iteraciones));
    final Map<String, Object?> r;
    try {
      r = await api!.llamar('pin', {'sal': sal, 'hash': hash});
    } on SinSenal {
      throw ApiError('sin_senal', 'Necesita señal para cambiar el PIN. Intente donde haya internet.');
    }
    _estado
      ..['pin'] = r['pin']
      ..['intentos_pin'] = 0
      ..['bloqueo_pin'] = false;
    desbloqueado = true;
    await _guardarEstado();
    notifyListeners();
  }

  /// Olvidó su PIN: avisa al supervisor. El PIN temporal que él asigne llega al sincronizar.
  Future<String> solicitarPin() async {
    if (api == null) throw ApiError('datos', 'El celular no está conectado a Odoo.');
    try {
      final r = await api!.llamar('solicitar_pin', {});
      return '${r['mensaje'] ?? 'Listo. Su supervisor ya tiene el aviso.'}';
    } on SinSenal {
      throw ApiError('sin_senal', 'Necesita señal para pedir un PIN nuevo. Si no hay, pida al supervisor un QR nuevo.');
    }
  }

  void bloquearPantalla() {
    if (pin == null) return;
    desbloqueado = false;
    notifyListeners();
  }

  // ---------------------------------------------------------------- lo que hace el vendedor

  /// Guarda una operación en la cola (siempre primero en el celular) y trata de subirla.
  Future<String> registrar(String tipo, Map<String, Object?> datos) async {
    if (tiposDeVenta.contains(tipo) && !puedeVender) {
      throw ApiError('datos', motivoNoVender!);
    }
    final visitaId = datos['visita_id'];
    if (visitaId is int && visitaId < 0) {
      // Cliente dado de alta sin señal: se liga a su alta, que Odoo procesa primero.
      final altas = (await cola!.pendientes(limite: 100000)).where((o) => o.tipo == 'cliente_nuevo');
      final alta = altas.where((o) => Ruta.idProvisional(o.uuid) == visitaId).firstOrNull;
      if (alta == null) throw ApiError('datos', 'El cliente nuevo ya no está en el celular. Sincronice.');
      datos = {...datos, 'visita_uuid': alta.uuid}..remove('visita_id');
    }
    final uuid = await cola!.agregar(tipo, datos);
    pendientes = await cola!.contarPendientes();
    notifyListeners();
    unawaited(sincronizar());
    return uuid;
  }

  Future<Object?> dato(String clave) async => base?.leer(clave);

  // ---------------------------------------------------------------- sincronización

  /// Latido, subir la cola y bajar lo que cambió. Sin señal no hace nada malo: todo queda para después.
  ///
  /// Si ya hay una sincronización en curso, devuelve esa misma (no se encima otra).
  Future<void> sincronizar({bool completo = false}) {
    if (api == null || base == null) return Future.value();
    return _enCurso ??= _sincronizar(completo).whenComplete(() => _enCurso = null);
  }

  Future<void>? _enCurso;

  Future<void> _sincronizar(bool completo) async {
    sincronizando = true;
    ultimoError = null;
    notifyListeners();
    try {
      final comandos = await _latido();
      var resincronizar = completo;
      var borrar = false;
      for (final c in comandos) {
        switch (c['tipo']) {
          case 'resincronizar':
            resincronizar = true;
          case 'borrar':
            borrar = true;
        }
      }
      if (!bloqueado) await _subir();
      if (borrar) {
        await _borrarTodo();
        return;
      }
      if (!bloqueado) {
        await _bajar(resincronizar);
        await _bajarImagenes();
      }
      _estado['ultima_sync'] = horaOdoo(reloj());
    } on SinSenal {
      _ultimaConexion = null;
      ultimoError = 'Sin señal. Lo capturado está guardado en el celular y se enviará después.';
    } on ApiError catch (e) {
      switch (e.codigo) {
        case 'token_invalido':
          noAutorizado = true;
        case 'dispositivo_bloqueado':
          _estado['bloqueado'] = true;
      }
      ultimoError = e.mensaje;
    } finally {
      sincronizando = false;
      if (base != null) {
        pendientes = await cola!.contarPendientes();
        await _guardarEstado();
      }
      notifyListeners();
    }
  }

  Future<List<Map>> _latido() async {
    final hechos = ((_estado['comandos_hechos'] as List?) ?? const []).cast<Object?>();
    final r = await api!.latido({
      'app_version': appVersion,
      'cola_pendiente': await cola!.contarPendientes(),
      'ultima_sync': _estado['ultima_sync'],
      'comandos_hechos': hechos,
    });
    noAutorizado = false;
    _ultimaConexion = reloj();
    // Con señal y el servidor de acuerdo, el bloqueo por PIN equivocado se levanta.
    _estado
      ..['bloqueo_pin'] = false
      ..['intentos_pin'] = 0
      ..['comandos_hechos'] = <int>[]
      ..['licencia'] = r['licencia']
      ..['version_minima'] = r['version_minima'] ?? '1.0.0'
      ..['actualizacion'] = r['actualizacion']
      ..['bloqueado'] = r['estado'] == 'bloqueado';
    if (r['trabajar_hasta'] is String) _estado['trabajar_hasta'] = r['trabajar_hasta'];
    if (r.containsKey('pin')) {
      _estado['pin'] = r['pin'];
      if (r['pin'] == null || r['pin'] == false) desbloqueado = true;
    }
    final servidor = r['servidor'] as String?;
    if (servidor != null) {
      // La hora del servidor manda: si el celular iba adelantado, la marca se corrige.
      _estado['hora_maxima'] = servidor;
    }
    final comandos = ((r['comandos'] as List?) ?? const []).whereType<Map>().toList();
    final nuevosHechos = <int>[];
    for (final c in comandos) {
      switch (c['tipo']) {
        case 'bloquear':
          _estado['bloqueado'] = true;
        case 'desbloquear':
          _estado['bloqueado'] = false;
      }
      if (c['id'] is int && c['tipo'] != 'borrar') nuevosHechos.add(c['id'] as int);
    }
    _estado['comandos_hechos'] = nuevosHechos;
    return comandos;
  }

  Future<void> _subir() async {
    // En lotes y en orden; si se cae la señal a medias, lo que falta sigue pendiente.
    for (var vuelta = 0; vuelta < 40; vuelta++) {
      final lote = await cola!.pendientes(limite: 50);
      if (lote.isEmpty) return;
      final resultados = await api!.subir(lote.map((o) => o.paraSubir()).toList());
      await cola!.aplicarResultados(resultados);
      if (resultados.length < lote.length) return;
      // Las que regresaron con error siguen pendientes: no se reintentan en la misma vuelta.
      final siguen = (await cola!.pendientes(limite: 50)).map((o) => o.uuid).toSet();
      if (lote.every((o) => siguen.contains(o.uuid))) return;
    }
  }

  Future<void> _bajar(bool completo) async {
    final marcas = completo ? <String, Object?>{} : ((await base!.leer('marcas')) as Map?)?.cast<String, Object?>() ?? {};
    final r = await api!.bajar(marcas);
    final guardar = <String, Object?>{};
    for (final parte in partesBajada) {
      if (r.containsKey(parte) && r[parte] != null) guardar[parte] = r[parte];
    }
    if (r['sesion'] is Map) {
      final s = (r['sesion'] as Map).cast<String, Object?>();
      _estado['sesion'] = {'usuario': s['usuario'], 'empresa': s['empresa'], 'dispositivo_id': s['dispositivo_id']};
      _estado['pin'] = s['pin'];
    }
    await base!.escribirVarios(guardar);
  }

  // ---------------------------------------------------------------- imágenes

  final _imagenes = <int, Uint8List?>{};

  /// La miniatura si ya está en memoria (para pintar sin parpadeo); `null` si hay que leerla con [imagen].
  (Uint8List?,)? imagenEnMemoria(int productoId) =>
      _imagenes.containsKey(productoId) ? (_imagenes[productoId],) : null;

  /// Miniatura guardada del producto, o null si no tiene (o aún no baja). Funciona sin señal.
  Future<Uint8List?> imagen(int productoId) async {
    if (_imagenes.containsKey(productoId)) return _imagenes[productoId];
    final b64 = await base?.leer('img:$productoId');
    final bytes = b64 is String && b64.isNotEmpty ? base64Decode(b64) : null;
    _imagenes[productoId] = bytes;
    return bytes;
  }

  /// Baja una sola vez las miniaturas nuevas o cambiadas del catálogo. Si falla, sigue sin fotos y reintenta en la
  /// siguiente sincronización.
  Future<void> _bajarImagenes() async {
    final jornadas = ((await base!.leer('jornadas')) as List?)?.whereType<Map>() ?? const <Map>[];
    final activas = jornadas.any((j) => (j['config'] as Map?)?['imagenes'] == true);
    if (!activas) return;
    final catalogo = ((await base!.leer('catalogo')) as List?)?.whereType<Map>() ?? const <Map>[];
    final versiones = ((await base!.leer('img_versiones')) as Map?)?.cast<String, Object?>() ?? <String, Object?>{};
    final faltan = <int>[];
    for (final p in catalogo) {
      final id = p['id'];
      final version = '${p['imagen'] ?? ''}';
      if (id is! int) continue;
      if (version.isEmpty) {
        if (versiones.remove('$id') != null) {
          await base!.borrarDato('img:$id');
          _imagenes.remove(id);
        }
      } else if (versiones['$id'] != version) {
        faltan.add(id);
      }
    }
    try {
      for (var i = 0; i < faltan.length && i < 400; i += 40) {
        final lote = faltan.sublist(i, i + 40 > faltan.length ? faltan.length : i + 40);
        final r = await api!.imagenes(lote);
        final guardar = <String, Object?>{};
        for (final id in lote) {
          final img = r['$id'];
          if (img is Map && img['b64'] is String) {
            guardar['img:$id'] = img['b64'];
            versiones['$id'] = img['version'] ?? '';
          } else {
            versiones['$id'] = catalogo.firstWhere((p) => p['id'] == id)['imagen'];
          }
          _imagenes.remove(id);
        }
        guardar['img_versiones'] = versiones;
        await base!.escribirVarios(guardar);
        notifyListeners();
      }
    } on SinSenal {
      return;
    } on ApiError {
      return;
    }
  }

  /// Comando "borrar" del supervisor: ya intentó subir lo pendiente; borra la base, el token y la llave.
  Future<void> _borrarTodo() async {
    await base?.close();
    base = null;
    cola = null;
    await borrarBase?.call();
    final instalacion = await almacen.leer(Claves.idInstalacion);
    await almacen.borrarTodo();
    if (instalacion != null) await almacen.escribir(Claves.idInstalacion, instalacion);
    api = null;
    _estado = {};
    desbloqueado = false;
    pendientes = 0;
  }
}
