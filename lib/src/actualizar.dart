import 'dart:io';

import 'package:flutter/services.dart';

import 'api.dart';
import 'motor.dart';

const _canal = MethodChannel('lat.odai.ruta/actualizar');

/// Descarga el APK de la versión nueva desde Odoo y abre el instalador de Android. Devuelve "ok" si se abrió el
/// instalador, o "permiso" si Android primero pidió permitir instalar apps de esta fuente (hay que volver a tocar
/// Actualizar después de permitirlo).
Future<String> actualizarApp(Motor motor, {void Function(double? avance)? avance}) async {
  final version = motor.actualizacion;
  final api = motor.api;
  if (version == null || api == null) throw ApiError('datos', 'No hay actualización pendiente.');
  final carpeta = await _canal.invokeMethod<String>('carpeta');
  if (carpeta == null) throw ApiError('datos', 'No se pudo preparar la descarga.');
  final archivo = File('$carpeta/odai-ruta-${version['version']}.apk');
  if (!await archivo.exists() || await archivo.length() == 0) {
    final parcial = File('${archivo.path}.parcial');
    await api.descargar('apk', {'id': version['id']}, parcial,
        avance: (recibidos, total) => avance?.call(total == null || total == 0 ? null : recibidos / total));
    await parcial.rename(archivo.path);
  }
  return await _canal.invokeMethod<String>('instalar', {'ruta': archivo.path}) ?? 'ok';
}
