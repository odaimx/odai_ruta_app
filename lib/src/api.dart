import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Falla que devolvió el servidor: `{"error": {"codigo", "mensaje"}}`.
///
/// Códigos: `token_invalido`, `dispositivo_bloqueado`, `licencia`, `version_app`, `datos`, `servidor`.
class ApiError implements Exception {
  ApiError(this.codigo, this.mensaje, [this.status = 0]);

  final String codigo;
  final String mensaje;
  final int status;

  @override
  String toString() => mensaje;
}

/// No hay señal o el servidor no contestó: lo hecho sigue en la cola y se reintenta después.
class SinSenal implements Exception {
  SinSenal([this.detalle = '']);

  final String detalle;

  @override
  String toString() => 'Sin señal';
}

/// Lee el QR del supervisor: `{"url", "db", "codigo"}`.
class DatosQr {
  DatosQr(this.url, this.db, this.codigo);

  final String url;
  final String db;
  final String codigo;

  static DatosQr leer(String texto, {bool permitirHttp = false}) {
    Object? json;
    try {
      json = jsonDecode(texto);
    } on FormatException {
      throw ApiError('datos', 'Ese código QR no es de Odai Ruta.');
    }
    if (json is! Map || json['url'] is! String || json['codigo'] is! String) {
      throw ApiError('datos', 'Ese código QR no es de Odai Ruta.');
    }
    final url = (json['url'] as String).trim().replaceAll(RegExp(r'/+$'), '');
    validarUrl(url, permitirHttp: permitirHttp);
    return DatosQr(url, (json['db'] as String?) ?? '', json['codigo'] as String);
  }
}

void validarUrl(String url, {bool permitirHttp = false}) {
  final uri = Uri.tryParse(url);
  final ok = uri != null && uri.host.isNotEmpty && (uri.scheme == 'https' || (permitirHttp && uri.scheme == 'http'));
  if (!ok) {
    throw ApiError('datos', 'El servidor debe usar https:// (conexión segura).');
  }
}

/// Cliente de `POST /odai_ruta_movil/v1/<accion>`.
///
/// Con varias bases en el servidor, primero abre `/web/login?db=<base>` para que la cookie de sesión quede en
/// esa base. La identidad no viene de la cookie sino del token del dispositivo.
class Api {
  Api({required this.url, required this.db, this.token, http.Client? cliente, this.espera = const Duration(seconds: 40)})
      : _cliente = cliente ?? http.Client();

  final String url;
  final String db;
  String? token;
  final Duration espera;
  final http.Client _cliente;
  String? _cookie;

  static const prefijo = '/odai_ruta_movil/v1';

  Future<void> _elegirBase() async {
    if (db.isEmpty || _cookie != null) return;
    final uri = Uri.parse('$url/web/login').replace(queryParameters: {'db': db});
    final peticion = http.Request('GET', uri)..followRedirects = false;
    final respuesta = await _cliente.send(peticion).timeout(espera);
    await respuesta.stream.drain<void>();
    final galleta = respuesta.headers['set-cookie'] ?? '';
    final sesion = RegExp(r'session_id=([^;,\s]+)').firstMatch(galleta);
    _cookie = sesion == null ? '' : 'session_id=${sesion.group(1)}';
  }

  Future<Map<String, Object?>> llamar(String accion, Map<String, Object?> cuerpo, {bool conToken = true}) async {
    try {
      await _elegirBase();
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (db.isNotEmpty) 'X-Odoo-Database': db,
        if (_cookie != null && _cookie!.isNotEmpty) 'Cookie': _cookie!,
        if (conToken && token != null) 'Authorization': 'Bearer $token',
      };
      final respuesta = await _cliente
          .post(Uri.parse('$url$prefijo/$accion'), headers: headers, body: jsonEncode(cuerpo))
          .timeout(espera);
      Object? json;
      try {
        json = jsonDecode(utf8.decode(respuesta.bodyBytes));
      } on FormatException {
        json = null;
      }
      if (respuesta.statusCode >= 200 && respuesta.statusCode < 300 && json is Map) {
        return json.cast<String, Object?>();
      }
      if (json is Map && json['error'] is Map) {
        final error = json['error'] as Map;
        throw ApiError(error['codigo'] as String? ?? 'servidor', error['mensaje'] as String? ?? 'Falla en el servidor.',
            respuesta.statusCode);
      }
      if (respuesta.statusCode == 404) {
        throw ApiError('servidor', 'El servidor no tiene instalado Odai Ruta Móvil.', 404);
      }
      if (respuesta.statusCode >= 500 || respuesta.statusCode == 429) {
        // Proxy caído, mantenimiento: se reintenta como si no hubiera señal.
        throw SinSenal('HTTP ${respuesta.statusCode}');
      }
      throw ApiError('servidor', 'Respuesta inesperada del servidor (${respuesta.statusCode}).', respuesta.statusCode);
    } on SocketException catch (e) {
      throw SinSenal(e.message);
    } on TimeoutException {
      throw SinSenal('tiempo agotado');
    } on http.ClientException catch (e) {
      throw SinSenal(e.message);
    } on HandshakeException catch (e) {
      throw SinSenal(e.message);
    }
  }

  Future<Map<String, Object?>> emparejar(String codigo, Map<String, Object?> dispositivo) =>
      llamar('emparejar', {'codigo': codigo, 'dispositivo': dispositivo}, conToken: false);

  Future<Map<String, Object?>> latido(Map<String, Object?> info) => llamar('latido', info);

  Future<Map<String, Object?>> bajar(Map<String, Object?> desde) => llamar('bajar', {'desde': desde});

  Future<List<Object?>> subir(List<Map<String, Object?>> operaciones) async {
    final r = await llamar('subir', {'operaciones': operaciones});
    return (r['resultados'] as List?) ?? const [];
  }

  void cerrar() => _cliente.close();
}
