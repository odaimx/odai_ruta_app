import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odai_ruta/src/almacen.dart';
import 'package:odai_ruta/src/base_local.dart';
import 'package:odai_ruta/src/motor.dart';
import 'package:odai_ruta/src/pantallas/entrega.dart';
import 'package:odai_ruta/src/ruta.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _entrega = {
  'id': 70,
  'name': 'WH/OUT/0070',
  'pedido_id': 7,
  'pedido': 'S00007',
  'total': 50.0,
  'contado': true,
  'facturas': [],
  'por_cobrar': 50.0,
  'lineas': [
    {'move_id': 701, 'product_id': 1, 'producto': 'Agua', 'cantidad': 5.0, 'uom': 'Pieza', 'precio': 10.0},
  ],
};

Future<Motor> _motor() async {
  final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: BaseLocal.crearTablas, singleInstance: false));
  final base = BaseLocal(db);
  final motor = Motor(almacen: AlmacenEnMemoria(), abrirBase: (_) async => base);
  motor.base = base;
  motor.cola = Cola(base);
  await base.escribirVarios({
    'jornadas': [
      {
        'jornada': {'id': 4, 'ruta': 'Reparto Norte', 'state': 'abierta'},
        'config': {
          'tipo_ruta': 'reparto',
          'moneda': {'symbol': r'$', 'position': 'before', 'decimals': 2},
        },
        'visitas': [
          {'id': 20, 'cliente': 'Tienda Contado', 'estado': 'pendiente', 'secuencia': 1, 'entregas': [_entrega]},
        ],
      }
    ],
  });
  return motor;
}

void main() {
  sqfliteFfiInit();

  test('reparto: la entrega en parte cobra solo lo entregado y el cobro en cola se descuenta', () async {
    final motor = await _motor();
    var ruta = await Ruta.cargar(motor);
    expect(ruta.esReparto(4), isTrue);
    var visita = ruta.visita(4, 20)!;
    expect(ruta.porCobrarEntrega(20, ruta.entregas(visita).first), 50.0);

    await motor.cola!.agregar('entrega', {
      'visita_id': 20,
      'resultado': 'parcial',
      'lineas': [
        {'move_id': 701, 'cantidad': 3.0}
      ],
    });
    ruta = await Ruta.cargar(motor);
    visita = ruta.visita(4, 20)!;
    expect(ruta.estado(visita), 'parcial');
    expect(ruta.porCobrarEntrega(20, ruta.entregas(visita).first), 30.0);
    expect(ruta.tablero(4).conPedido, 1, reason: 'Entregado cuenta en el tablero');

    await motor.cola!.agregar('anticipo', {'visita_id': 20, 'pedido_id': 7, 'monto': 30.0});
    ruta = await Ruta.cargar(motor);
    expect(ruta.porCobrarEntrega(20, ruta.entregas(ruta.visita(4, 20)!).first), 0.0);
  });

  test('reparto: no entregado no cobra', () async {
    final motor = await _motor();
    await motor.cola!.agregar('entrega', {'visita_id': 20, 'resultado': 'no', 'motivo_id': 1});
    final ruta = await Ruta.cargar(motor);
    final visita = ruta.visita(4, 20)!;
    expect(ruta.estado(visita), 'no_entregado');
    expect(ruta.porCobrarEntrega(20, ruta.entregas(visita).first), 0.0);
    expect(ruta.tablero(4).sinVenta, 1);
  });

  testWidgets('pantalla de entrega: empieza con todo y al quitar piezas pasa a entrega en parte', (tester) async {
    late Motor motor;
    await tester.runAsync(() async => motor = await _motor());
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PantallaEntrega(motor: motor, jornadaId: 4, visitaId: 20)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    expect(find.text('S00007'), findsOneWidget);
    expect(find.text(r'Entregar todo · $50.00'), findsOneWidget);
    expect(find.byKey(const ValueKey('no_entregado')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('menos_701')));
    await tester.tap(find.byKey(const ValueKey('menos_701')));
    await tester.pump();
    expect(find.text('3'), findsOneWidget);
    expect(find.text(r'Entregar así · $30.00'), findsOneWidget);
  });
}
