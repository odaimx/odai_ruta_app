import 'dart:convert';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secretos del celular: token del dispositivo, servidor, base y llave de la base local. En Android viven en el
/// almacén seguro (cifrado con una llave del Android Keystore), nunca en la base local ni en archivos.
abstract class Almacen {
  Future<String?> leer(String clave);
  Future<void> escribir(String clave, String valor);
  Future<void> borrar(String clave);
  Future<void> borrarTodo();
}

class AlmacenSeguro implements Almacen {
  AlmacenSeguro([FlutterSecureStorage? storage]) : _s = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _s;

  @override
  Future<String?> leer(String clave) => _s.read(key: clave);

  @override
  Future<void> escribir(String clave, String valor) => _s.write(key: clave, value: valor);

  @override
  Future<void> borrar(String clave) => _s.delete(key: clave);

  @override
  Future<void> borrarTodo() => _s.deleteAll();
}

/// Para pruebas.
class AlmacenEnMemoria implements Almacen {
  final Map<String, String> datos = {};

  @override
  Future<String?> leer(String clave) async => datos[clave];

  @override
  Future<void> escribir(String clave, String valor) async => datos[clave] = valor;

  @override
  Future<void> borrar(String clave) async => datos.remove(clave);

  @override
  Future<void> borrarTodo() async => datos.clear();
}

/// Claves del almacén.
abstract final class Claves {
  static const url = 'url';
  static const db = 'db';
  static const token = 'token';
  static const llaveBase = 'llave_base';
  static const idInstalacion = 'id_instalacion';
}

String aleatorioBase64(int bytes) {
  final r = Random.secure();
  return base64UrlEncode(List<int>.generate(bytes, (_) => r.nextInt(256))).replaceAll('=', '');
}

/// La llave de la base local: se crea una vez por instalación y solo vive en el almacén seguro.
Future<String> llaveBaseLocal(Almacen almacen) async {
  var llave = await almacen.leer(Claves.llaveBase);
  if (llave == null || llave.isEmpty) {
    llave = aleatorioBase64(32);
    await almacen.escribir(Claves.llaveBase, llave);
  }
  return llave;
}
