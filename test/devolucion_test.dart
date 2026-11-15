import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odai_ruta/src/almacen.dart';
import 'package:odai_ruta/src/base_local.dart';
import 'package:odai_ruta/src/motor.dart';
import 'package:odai_ruta/src/pantallas/devolucion.dart';
import 'package:odai_ruta/src/ruta.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Map _pedido({String oficina = ''}) => {
  'id': 9,
  'name': 'S00009',
  'state': 'sale',
  'total': 50.0,
  'devolucion_oficina': oficina,
  'lineas': [
    {'id': 91, 'producto': 'Agua', 'cantidad': 5.0, 'uom': 'Pieza', 'precio': 10.0},
  ],
};

Future<Motor> _motor() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 1, onCreate: BaseLocal.crearTablas, singleInstance: false),
  );
  final base = BaseLocal(db);
  final motor = Motor(almacen: AlmacenEnMemoria(), abrirBase: (_) async => base);
  motor.base = base;
  motor.cola = Cola(base);
  await base.escribirVarios({
    'jornadas': [
      {
        'jornada': {'id': 4, 'ruta': 'Norte', 'state': 'abierta', 'monto': 50.0},
        'config': {
          'moneda': {'symbol': r'$', 'position': 'before', 'decimals': 2},
        },
        'motivos_devolucion': [
          {'id': 3, 'name': 'Producto dañado'},
        ],
        'visitas': [
          {
            'id': 20,
            'cliente': 'Tienda',
            'estado': 'pedido',
            'secuencia': 1,
            'pedidos': [_pedido()],
          },
        ],
      },
    ],
  });
  return motor;
}

void main() {
  sqfliteFfiInit();

  test('devolución en cola resta de lo vendido y no se repite', () async {
    final motor = await _motor();
    await motor.cola!.agregar('devolucion', {
      'visita_id': 20,
      'pedido_id': 9,
      'todo': false,
      'monto': 20.0,
      'oficina': false,
      'lineas': [
        {'linea_id': 91, 'cantidad': 2.0},
      ],
    });
    final ruta = await Ruta.cargar(motor);
    expect(ruta.tablero(4).vendido, 30.0);
    expect(ruta.devolucionEnCola(20, 9), isNotNull);
    expect(ruta.motivosDevolucion(4).single['name'], 'Producto dañado');
  });

  testWidgets('pantalla de devolución: pide productos y motivo; avisa si la revisa la oficina', (tester) async {
    late Motor motor;
    await tester.runAsync(() async => motor = await _motor());
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: PantallaDevolucion(
          motor: motor,
          jornadaId: 4,
          visitaId: 20,
          pedido: _pedido(oficina: 'Ya está facturado.'),
        ),
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('devolucion_oficina')), findsOneWidget);
    expect(find.text('Enviar a la oficina'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('dev_mas_91')));
    await tester.tap(find.byKey(const ValueKey('dev_mas_91')));
    await tester.pump();
    expect(find.text(r'Devuelve $20.00'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('devolver_todo')));
    await tester.pump();
    expect(find.text(r'Devuelve $50.00'), findsOneWidget);
    expect(find.text('Producto dañado'), findsOneWidget);
  });
}
