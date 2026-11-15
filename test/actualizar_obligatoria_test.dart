import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odai_ruta/src/almacen.dart';
import 'package:odai_ruta/src/motor.dart';
import 'package:odai_ruta/src/pantallas/actualizar_obligatoria.dart';

void main() {
  testWidgets('versión obligatoria: pantalla completa con Sincronizar y aviso si falta el archivo', (tester) async {
    final motor = Motor(almacen: AlmacenEnMemoria(), abrirBase: (_) async => throw UnimplementedError());
    await tester.pumpWidget(MaterialApp(home: PantallaActualizarObligatoria(motor: motor)));
    expect(find.byKey(const ValueKey('actualizar_obligatoria')), findsOneWidget);
    expect(find.text('Sincronizar'), findsOneWidget);
    expect(find.textContaining('aún no sube el archivo'), findsOneWidget);
  });
}
