import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odai_ruta/src/version.dart';

void main() {
  test('appVersion coincide con la versión de pubspec.yaml', () {
    // Si no coinciden, el celular reporta otra versión y el servidor le pide actualizar sin fin.
    final linea = File('pubspec.yaml').readAsLinesSync().firstWhere((l) => l.startsWith('version:'));
    final version = linea.split(':')[1].trim().split('+').first;
    expect(appVersion, version);
  });
}
