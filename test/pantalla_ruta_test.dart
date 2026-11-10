import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odai_ruta/src/almacen.dart';
import 'package:odai_ruta/src/base_local.dart';
import 'package:odai_ruta/src/motor.dart';
import 'package:odai_ruta/src/pantallas/ruta.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  testWidgets('ruta: por omisión solo los pendientes; filtros Visitados y Todos; acciones en una barra', (tester) async {
    late Motor motor;
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
            'config': {'moneda': {'symbol': r'$', 'position': 'before', 'decimals': 2}},
            'visitas': [
              {'id': 10, 'cliente': 'Lupita', 'estado': 'pendiente', 'secuencia': 1},
              {'id': 11, 'cliente': 'Don Pepe', 'estado': 'pedido', 'secuencia': 2},
            ],
          }
        ],
      });
    });
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PantallaRuta(motor: motor, jornadaId: 3)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('accion_Nuevo cliente')), findsOneWidget);
    expect(find.byKey(const ValueKey('accion_Cerrar jornada')), findsOneWidget);
    expect(find.text('Lupita'), findsOneWidget);
    expect(find.text('Don Pepe'), findsNothing, reason: 'Los visitados no estorban al buscar');

    await tester.tap(find.text('Visitados (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Lupita'), findsNothing);
    expect(find.text('Don Pepe'), findsOneWidget);

    await tester.tap(find.text('Todos (2)'));
    await tester.pumpAndSettle();
    expect(find.text('Lupita'), findsOneWidget);
    expect(find.text('Don Pepe'), findsOneWidget);
  });
}
