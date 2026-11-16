import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:odai_ruta/src/almacen.dart';
import 'package:odai_ruta/src/base_local.dart';
import 'package:odai_ruta/src/motor.dart';
import 'package:odai_ruta/src/pantallas/ruta.dart';
import 'package:odai_ruta/src/ruta.dart';
import 'package:odai_ruta/src/ubicacion.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class UbicadorFijo implements Ubicador {
  UbicadorFijo(this.lat, this.lon);

  double lat;
  double lon;

  @override
  Future<Posicion?> actual() async => Posicion(lat, lon, precision: 5);
}

Future<Motor> _motor() async {
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 1, onCreate: BaseLocal.crearTablas, singleInstance: false),
  );
  final base = BaseLocal(db);
  final motor = Motor(almacen: AlmacenEnMemoria(), abrirBase: (_) async => base);
  motor.base = base;
  motor.cola = Cola(base);
  motor.ubicador = UbicadorFijo(19.4326, -99.1332);
  motor.seguimiento = true;
  await base.escribirVarios({
    'jornadas': [
      {
        'jornada': {'id': 4, 'ruta': 'Norte', 'state': 'abierta'},
        'config': {
          'moneda': {'symbol': r'$', 'position': 'before', 'decimals': 2},
          'mapa': {
            'teselas': {'url': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', 'atribucion': '© OpenStreetMap'},
            'seguimiento': true,
            'punto_cada_s': 120,
            'punto_metros': 100,
            'aviso': '',
          },
        },
        'visitas': [
          {'id': 20, 'cliente': 'Lupita', 'estado': 'pendiente', 'secuencia': 10, 'latitud': 19.43, 'longitud': -99.13},
          {
            'id': 21,
            'cliente': 'Contado',
            'estado': 'pendiente',
            'secuencia': 20,
            'latitud': 19.44,
            'longitud': -99.14,
          },
          {'id': 22, 'cliente': 'Sin ubicación', 'estado': 'pendiente', 'secuencia': 30},
        ],
      },
    ],
  });
  return motor;
}

void main() {
  sqfliteFfiInit();

  test('distancia y salida automática con GPS al cerrar la visita', () async {
    expect(distanciaM(19.4326, -99.1332, 19.4326, -99.1312), closeTo(210, 5));
    final motor = await _motor();
    await motor.marcarVisita(20, 'llegada');
    await motor.marcarVisita(20, 'llegada');
    await motor.registrar('sin_venta', {'visita_id': 20, 'motivo_id': 1});
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final ops = await motor.cola!.pendientes(limite: 100);
    final gps = ops.where((o) => o.tipo == 'gps').toList();
    expect(gps.map((o) => o.datos['evento']), ['llegada', 'salida'], reason: 'La llegada se manda una sola vez');
    expect(gps.first.datos['lat'], 19.4326);
    expect(gps.first.datos['momento'], endsWith('Z'));
    final ruta = await Ruta.cargar(motor);
    expect(ruta.llegada(ruta.visita(4, 20)!), isTrue);
    expect(ruta.llegada(ruta.visita(4, 21)!), isFalse);
  });

  test('sin el seguimiento GPS en Odoo no se manda ubicación', () async {
    final motor = await _motor();
    motor.seguimiento = false;
    await motor.marcarVisita(20, 'llegada');
    await motor.registrar('sin_venta', {'visita_id': 20, 'motivo_id': 1});
    expect(await motor.fijarUbicacion(20), isFalse);
    motor.iniciarRecorrido(4, cada: const Duration(minutes: 2));
    expect(motor.grabandoRecorrido, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final tipos = (await motor.cola!.pendientes(limite: 100)).map((o) => o.tipo).toSet();
    expect(tipos.intersection({'gps', 'ubicacion', 'puntos'}), isEmpty);
    final ruta = await Ruta.cargar(motor);
    expect(ruta.seguimiento(4), isTrue);
  });

  test('el orden del día en la cola manda en la lista', () async {
    final motor = await _motor();
    await motor.registrar('orden', {
      'jornada_id': 4,
      'visitas': [21, 20, 22],
    });
    final ruta = await Ruta.cargar(motor);
    expect(ruta.visitas(4).map((v) => v['id']), [21, 20, 22]);
    expect(ruta.jornadaEnRuta(), 4);
    expect(ruta.mapa(4)['punto_cada_s'], 120);
  });

  test('recorrido: guarda puntos al moverse y los manda en grupo', () async {
    final motor = await _motor();
    final ubicador = motor.ubicador! as UbicadorFijo;
    motor.iniciarRecorrido(4, cada: const Duration(hours: 1), metros: 100);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await motor.tomarPunto(cada: const Duration(hours: 1), metros: 100);
    ubicador.lat += 0.002; // unos 220 m
    await motor.tomarPunto(cada: const Duration(hours: 1), metros: 100);
    motor.detenerRecorrido();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final puntos = (await motor.cola!.pendientes(limite: 100)).where((o) => o.tipo == 'puntos').toList();
    expect(puntos, hasLength(1));
    expect((puntos.single.datos['puntos'] as List), hasLength(2), reason: 'El segundo punto sin moverse no cuenta');
    final trayecto = await motor.trayecto(4);
    expect(trayecto, hasLength(2), reason: 'El trayecto del día queda en el celular para dibujarlo');
    expect(trayecto.last.lat, closeTo(ubicador.lat, 1e-9));
  });

  testWidgets('ruta: cambiar a mapa y ordenar con flechas', (tester) async {
    late Motor motor;
    await tester.runAsync(() async => motor = await _motor());
    tester.view.physicalSize = const Size(900, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: PantallaRuta(motor: motor, jornadaId: 4)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('ordenar')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('bajar_20')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    final orden = await tester.runAsync(
      () async => (await motor.cola!.pendientes(limite: 100)).where((o) => o.tipo == 'orden').single.datos['visitas'],
    );
    expect(orden, [21, 20, 22]);

    await tester.tap(find.byKey(const ValueKey('vista_mapa')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump();
    expect(find.byKey(const ValueKey('pin_20')), findsOneWidget);
    expect(find.byKey(const ValueKey('pin_21')), findsOneWidget);
    expect(find.byKey(const ValueKey('sin_ubicacion')), findsOneWidget);
    expect(find.byType(PolylineLayer), findsOneWidget, reason: 'Clientes unidos en orden y trayecto');
  });
}
