import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PIN del vendedor. Odoo lo guarda como PBKDF2-HMAC-SHA256 con sal (hex) y manda a la app solo
/// `{sal, hash, iteraciones}`; la app lo valida sin señal, sin conocer el PIN.
class DatosPin {
  const DatosPin({required this.sal, required this.hash, required this.iteraciones});

  final String sal;
  final String hash;
  final int iteraciones;

  static DatosPin? desdeJson(Object? json) {
    if (json is! Map) return null;
    final sal = json['sal'], hash = json['hash'], iteraciones = json['iteraciones'];
    if (sal is! String || hash is! String || iteraciones is! int) return null;
    return DatosPin(sal: sal, hash: hash, iteraciones: iteraciones);
  }

  Map<String, Object> aJson() => {'sal': sal, 'hash': hash, 'iteraciones': iteraciones};
}

Uint8List _deHex(String hex) {
  final bytes = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < bytes.length; i++) {
    bytes[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return bytes;
}

String _aHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// PBKDF2-HMAC-SHA256 con un bloque de 32 bytes, igual que `hashlib.pbkdf2_hmac('sha256', ...)`.
String pbkdf2Sha256Hex(String pin, String salHex, int iteraciones) {
  final hmac = Hmac(sha256, utf8.encode(pin));
  final sal = _deHex(salHex);
  final primero = Uint8List(sal.length + 4)
    ..setAll(0, sal)
    ..setAll(sal.length, [0, 0, 0, 1]);
  var u = hmac.convert(primero).bytes;
  final resultado = Uint8List.fromList(u);
  for (var i = 1; i < iteraciones; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < resultado.length; j++) {
      resultado[j] ^= u[j];
    }
  }
  return _aHex(resultado);
}

/// Sal nueva de 16 bytes en hex (32 caracteres), con el generador seguro del sistema.
String nuevaSal() {
  final azar = Random.secure();
  return _aHex(List.generate(16, (_) => azar.nextInt(256)));
}

/// Compara en tiempo constante.
bool _iguales(String a, String b) {
  if (a.length != b.length) return false;
  var diferencia = 0;
  for (var i = 0; i < a.length; i++) {
    diferencia |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diferencia == 0;
}

bool verificarPinSincrono(String pin, DatosPin datos) =>
    _iguales(pbkdf2Sha256Hex(pin, datos.sal, datos.iteraciones), datos.hash.toLowerCase());

/// Valida el PIN en otro hilo: son 120 000 vueltas y no deben congelar la pantalla.
Future<bool> verificarPin(String pin, DatosPin datos) =>
    Isolate.run(() => verificarPinSincrono(pin, datos));
