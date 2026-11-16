import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odai_ruta/src/almacen.dart';
import 'package:odai_ruta/src/base_local.dart';
import 'package:odai_ruta/src/motor.dart';
import 'package:odai_ruta/src/pantallas/pedido.dart';
import 'package:odai_ruta/src/ruta.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Un catálogo como el del cliente: 2,500 productos con embalajes y el 30 % con atributos (4 variantes).
List<Map<String, Object?>> catalogoGrande() {
  final r = <Map<String, Object?>>[];
  var id = 1;
  for (var t = 1; t <= 2500; t++) {
    final embalajes = [
      {'id': 9, 'name': 'Paquete de 6', 'factor': 6, 'precio': 60.0},
      {'id': 10, 'name': 'Caja de 12', 'factor': 12, 'precio': 120.0},
    ];
    if (t % 10 < 3) {
      for (final sabor in ['Cola', 'Limón']) {
        for (final tamano in ['600 ml', '2 L']) {
          r.add({
            'id': id,
            'name': 'Producto $t ($sabor, $tamano)',
            'code': 'P$t-$sabor-$tamano',
            'precio': 10.0,
            'uom_id': 1,
            'uom': 'Pza.',
            'barcodes': {'75$id': 1, 'CJ$id': 10},
            'uoms': embalajes,
            'plantilla': t,
            'plantilla_nombre': 'Producto $t',
            'atributos': [
              ['Sabor', sabor],
              ['Tamaño', tamano],
            ],
            'imagen': '1',
            'imagen_id': id - id % 4 + 1,
          });
          id++;
        }
      }
    } else {
      r.add({
        'id': id,
        'name': 'Producto $t',
        'code': 'P$t',
        'precio': 10.0,
        'uom_id': 1,
        'uom': 'Pza.',
        'barcodes': {'75$id': 1},
        'uoms': embalajes,
      });
      id++;
    }
  }
  return r;
}

void main() {
  sqfliteFfiInit();

  Future<(Motor, BaseLocal)> motorCon(List<Map<String, Object?>> catalogo) async {
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
          'jornada': {'id': 3, 'ruta': 'Ruta Norte', 'state': 'abierta'},
          'config': {
            'moneda': {'symbol': r'$', 'position': 'before', 'decimals': 2},
          },
          'visitas': [
            {
              'id': 10,
              'cliente': 'Lupita',
              'estado': 'pendiente',
              'secuencia': 1,
              'credito': {'a_credito': true},
            },
          ],
        },
      ],
      'catalogo': catalogo,
      'listas': <String, Object?>{},
      'visita_lista': {'10': '0'},
    });
    return (motor, base);
  }

  test('catálogo grande: se guarda en partes, se lee igual y se agrupa por producto', () async {
    final catalogo = catalogoGrande();
    expect(catalogo, hasLength(1750 + 750 * 4));
    final (motor, base) = await motorCon(catalogo);
    final filas = await base.db.query('datos', where: 'clave LIKE ?', whereArgs: ['catalogo#%']);
    expect(filas.length, greaterThan(1), reason: 'Android no lee renglones de más de 2 MB');
    expect(filas.every((f) => (f['valor'] as String).length <= BaseLocal.tamanoParte), isTrue);
    final ruta = await Ruta.cargar(motor);
    expect(ruta.catalogo, hasLength(catalogo.length));
    expect(ruta.catalogo.last['name'], catalogo.last['name']);
    // Al reemplazarlo por uno chico se borran las partes que sobran.
    await base.escribir('catalogo', catalogo.take(3).toList());
    expect(await base.db.query('datos', where: 'clave LIKE ?', whereArgs: ['catalogo#%']), isEmpty);
    expect((await base.leer('catalogo') as List), hasLength(3));
    await base.escribir('catalogo', catalogo);

    final ruta2 = await Ruta.cargar(motor);
    final variante = ruta2.catalogo.firstWhere((p) => p['plantilla'] == 1);
    expect(ruta2.variantes(variante), hasLength(4));
    expect(ruta2.variantes(ruta2.catalogo.firstWhere((p) => p['plantilla'] == null)), isEmpty);
    final reloj = Stopwatch()..start();
    final encontrados = ruta2.buscar('producto 1');
    expect(reloj.elapsedMilliseconds, lessThan(500));
    // 80 tarjetas: las variantes de un producto cuentan como una.
    final tarjetas = {for (final p in encontrados) p['plantilla'] ?? 'p${p['id']}'};
    expect(tarjetas, hasLength(80));
    expect(ruta2.buscar('CJ2').single['id'], 2, reason: 'Código de caja de una variante');
    expect(ruta2.porCodigo('CJ2')!.$1['id'], 2);
    expect(ruta2.porCodigo('CJ2')!.$2, 10);
  });

  testWidgets('pedido: una tarjeta por producto; se elige sabor y tamaño y luego el embalaje', (tester) async {
    late Motor motor;
    await tester.runAsync(
      () async => motor = (await motorCon([
        for (final p in catalogoGrande().take(12)) {...p}..remove('imagen'),
      ])).$1,
    );
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PantallaPedido(motor: motor, jornadaId: 3, visitaId: 10)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();

    // Producto 1 tiene 4 variantes (ids 1 a 4): una sola tarjeta, con la primera elegida.
    expect(find.byKey(const ValueKey('producto_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('producto_2')), findsNothing);
    expect(find.text('PRODUCTO 1'), findsOneWidget);
    // Tamaño 2 L: pasa a la variante (Cola, 2 L), id 2.
    // Un desplegable por atributo.
    await tester.tap(find.byKey(const ValueKey('atributo_1_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2 L').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('producto_2')), findsOneWidget);
    // Sabor Limón conservando 2 L: (Limón, 2 L), id 4.
    await tester.tap(find.byKey(const ValueKey('atributo_1_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limón').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('producto_4')), findsOneWidget);
    // Embalaje y agregar.
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('producto_4')), matching: find.text('Caja de 12')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agregar_4')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1 producto'), findsOneWidget);
    // Otra variante: se ve lo que ya va en el pedido.
    await tester.tap(find.byKey(const ValueKey('atributo_1_0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cola').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('producto_2')), findsOneWidget);
    expect(find.textContaining('En el pedido: 1 Limón 2 L'), findsOneWidget);
  });

  testWidgets('kits: el incompleto no se vende y no pasa de lo que se puede armar', (tester) async {
    late Motor motor;
    await tester.runAsync(
      () async => motor = (await motorCon([
        {'id': 900, 'name': 'Kit vaso', 'precio': 10.0, 'uom': 'Pieza', 'existencia': 2,
         'kit': [{'name': 'Vaso', 'cantidad': 1.0}, {'name': 'Hielo', 'cantidad': 1.0}]},
        {'id': 901, 'name': 'Kit incompleto', 'precio': 10.0, 'uom': 'Pieza', 'existencia': 0,
         'kit': [{'name': 'Tapa', 'cantidad': 1.0}]},
      ])).$1,
    );
    tester.view.physicalSize = const Size(400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PantallaPedido(motor: motor, jornadaId: 3, visitaId: 10)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pumpAndSettle();
    expect(find.text('KIT: 1.0 Vaso, 1.0 Hielo'), findsOneWidget);
    expect(find.text('Sin existencia para armarlo'), findsOneWidget);
    expect(tester.widget<OutlinedButton>(find.byKey(const ValueKey('agregar_901'))).onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('agregar_900')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(find.text('Solo hay existencia para 2 kits de Kit vaso.'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));
    expect(find.descendant(of: find.byKey(const ValueKey('producto_900')), matching: find.text('2')), findsOneWidget);
  });
}
