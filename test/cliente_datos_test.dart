import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odai_ruta/src/almacen.dart';
import 'package:odai_ruta/src/base_local.dart';
import 'package:odai_ruta/src/motor.dart';
import 'package:odai_ruta/src/pantallas/cliente_datos.dart';
import 'package:odai_ruta/src/ruta.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('editar cliente: salen sus datos actuales, incluidos los fiscales, y se guardan sin señal',
      (tester) async {
    late Motor motor;
    late Map visita;
    await tester.runAsync(() async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(version: 1, onCreate: BaseLocal.crearTablas, singleInstance: false));
      final base = BaseLocal(db);
      motor = Motor(almacen: AlmacenEnMemoria(), abrirBase: (_) async => base);
      motor.base = base;
      motor.cola = Cola(base);
      await base.escribirVarios({
        'jornadas': [
          {
            'jornada': {'id': 3, 'ruta': 'Ruta Norte', 'state': 'abierta'},
            'config': {
              'catalogos_fiscales': {
                'regimen': [
                  {'id': 1, 'name': '601-General de Ley', 'clave': '601'},
                  {'id': 2, 'name': '612-Personas Físicas', 'clave': '612'},
                ],
                'uso': [{'id': 5, 'name': 'G03-Gastos en general', 'clave': 'G03'}],
                'forma': [{'id': 7, 'name': '01-Efectivo', 'clave': '01'}],
                'metodo': [{'id': 9, 'name': 'PUE-Pago en una sola exhibición', 'clave': 'PUE'}],
              },
              'catalogos_direccion': {
                'mexico': 156,
                'paises': [{'id': 156, 'name': 'México'}],
                'estados': [{'id': 14, 'name': 'Jalisco', 'pais': 156}],
              },
            },
            'visitas': [
              {
                'id': 10, 'cliente': 'Lupita', 'estado': 'pendiente', 'telefono': '3311112222',
                'contacto': {'nombre': 'Lupita Pérez', 'telefono': '3311112222', 'calle': 'Juárez 4', 'cp': '44100', 'estado': 14, 'pais': 156},
                'fiscal': {'rfc': 'LUPA800101AB1', 'razon_social': 'Lupita Pérez', 'cp': '44100', 'regimen': 2, 'uso': 5},
              },
            ],
          }
        ],
      });
      visita = (await Ruta.cargar(motor)).visita(3, 10)!;
    });
    tester.view.physicalSize = const Size(800, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PantallaDatosCliente(motor: motor, jornadaId: 3, visita: visita)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('Juárez 4'), findsOneWidget);
    expect(find.text('3311112222'), findsOneWidget);
    expect(find.text('LUPA800101AB1'), findsOneWidget);
    expect(find.text('Lupita Pérez'), findsOneWidget);
    expect(find.text('LUPITA PÉREZ'), findsOneWidget, reason: 'El nombre fiscal se toma del nombre');
    expect(find.text('612-Personas Físicas'), findsOneWidget);
    expect(find.text('G03-Gastos en general'), findsOneWidget);
    expect(find.text('Jalisco'), findsOneWidget);
    expect(find.text('México'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Juárez 4'), 'Hidalgo 10');
    await tester.tap(find.text('Guardar'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump();
    final ops = await tester.runAsync(() => motor.cola!.pendientes(limite: 10));
    final cambio = ops!.single;
    expect(cambio.tipo, 'cliente');
    expect(cambio.datos['contacto'], {'calle': 'Hidalgo 10'});
    expect(cambio.datos.containsKey('fiscal'), isFalse, reason: 'Los datos fiscales no cambiaron');
  });
}
