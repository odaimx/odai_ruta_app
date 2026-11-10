import 'package:flutter_test/flutter_test.dart';
import 'package:odai_ruta/src/almacen.dart';
import 'package:odai_ruta/src/base_local.dart';
import 'package:odai_ruta/src/motor.dart';
import 'package:odai_ruta/src/ruta.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  late Motor motor;

  setUp(() async {
    final almacen = AlmacenEnMemoria();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: 1, onCreate: BaseLocal.crearTablas, singleInstance: false));
    final base = BaseLocal(db);
    motor = Motor(almacen: almacen, abrirBase: (_) async => base);
    motor.base = base;
    motor.cola = Cola(base);
    await base.escribirVarios({
      'jornadas': [
        {
          'jornada': {'id': 3, 'ruta': 'Ruta Norte', 'state': 'abierta'},
          'config': {'moneda': {'symbol': r'$', 'position': 'before', 'decimals': 2}},
          'visitas': [
            {'id': 10, 'cliente': 'Lupita', 'estado': 'pendiente', 'secuencia': 2},
            {'id': 11, 'cliente': 'Contado', 'estado': 'sin_venta', 'secuencia': 1},
            {'id': 12, 'cliente': 'Tercero', 'estado': 'pendiente', 'secuencia': 3},
          ],
        }
      ],
      'catalogo': [
        {'id': 1, 'name': 'Refresco', 'precio': 20.0, 'uom_id': 1, 'uom': 'Pieza', 'barcodes': {'750': 1, '751': 9},
         'uoms': [{'id': 9, 'name': 'Caja de 12', 'factor': 12, 'precio': 240.0}]},
        {'id': 2, 'name': 'Combo', 'precio': 50.0, 'combo': [{'id': 1}]},
      ],
      'listas': {'5': {'1': 18.0, '1:9': 200.0}},
      'visita_lista': {'10': '5', '12': '0'},
      'iva': {'1': 1.16},
      'facturas': {
        '10': [
          {'id': 100, 'name': 'F1', 'saldo': 300.0},
          {'id': 101, 'name': 'F2', 'saldo': 200.0},
        ]
      },
    });
  });

  test('precios por lista y embalaje, con IVA', () async {
    final ruta = await Ruta.cargar(motor);
    final refresco = ruta.catalogo.first;
    expect(ruta.catalogo, hasLength(1), reason: 'Los combos aún no se venden desde la app');
    expect(ruta.precio(10, refresco), 18.0);
    expect(ruta.precio(10, refresco, uomId: 9), 200.0);
    expect(ruta.precio(12, refresco), 20.0, reason: 'Sin lista: precio de venta');
    expect(ruta.precio(12, refresco, uomId: 9), 240.0);
    final lineas = [Linea(producto: refresco, cantidad: 2), Linea(producto: refresco, cantidad: 1, uomId: 9)];
    expect(ruta.subtotal(10, lineas), 236.0);
    expect(ruta.total(10, lineas), closeTo(273.76, 0.001));
    final porCodigo = ruta.porCodigo('751')!;
    expect(porCodigo.$2, 9);
    expect(ruta.porCodigo('750')!.$2, isNull);
    expect(ruta.buscar('refres'), hasLength(1));
    expect(const Moneda()(1234.5), r'$1,234.50');
  });

  test('lo que espera en la cola ya se ve: visita con pedido y facturas abonadas', () async {
    await motor.cola!.agregar('pedido', {'visita_id': 10, 'total': 100.0});
    await motor.cola!.agregar('cobro', {'visita_id': 10, 'monto': 350.0, 'factura_ids': []});
    final ruta = await Ruta.cargar(motor);
    final visitas = ruta.visitas(3);
    expect(visitas.map((v) => v['id']), [12, 11, 10], reason: 'Pendientes primero; la 10 ya tiene pedido en la cola');
    expect(ruta.estado(visitas[2]), 'pedido');
    expect(ruta.pedidoEnCola(10), 100.0);
    final facturas = ruta.facturas(10);
    expect(facturas.map((f) => f['id']), [101]);
    expect(ruta.porCobrar(10), 150.0);
    final tablero = ruta.tablero(3);
    expect(tablero.vendido, 100.0);
    expect(tablero.cobrado, 350.0);
    expect([tablero.visitas, tablero.hechas, tablero.conPedido, tablero.sinVenta, tablero.pendientes], [3, 2, 1, 1, 1]);
  });
}
