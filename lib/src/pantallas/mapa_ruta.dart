import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../motor.dart';
import '../ruta.dart';
import '../tema.dart';
import 'comun.dart';

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;

/// Ubicación del cliente de la visita, o null si no tiene.
LatLng? puntoDe(Map visita) {
  final lat = _num(visita['latitud']), lon = _num(visita['longitud']);
  if (lat == 0 && lon == 0) return null;
  return LatLng(lat, lon);
}

/// Color del marcador según el estado de la visita; el siguiente pendiente va en azul.
Color colorEstado(String estado, {bool siguiente = false}) {
  if (estado == 'pendiente') return siguiente ? azulOdai : const Color(0xFF8D8D8D);
  if (estado == 'pedido' || estado == 'entregado' || estado == 'parcial') return verdeOdai;
  if (estado == 'sin_venta' || estado == 'no_entregado') return const Color(0xFFEF6C00);
  return const Color(0xFF5F5F5F);
}

/// Abre Google Maps o Waze para llegar al cliente (sin costo: es la app del celular).
Future<void> comoLlegar(BuildContext context, LatLng punto) async {
  final app = await showModalBottomSheet<String>(
    context: context,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.map),
            title: const Text('Google Maps'),
            onTap: () => Navigator.pop(context, 'google'),
          ),
          ListTile(
            leading: const Icon(Icons.navigation),
            title: const Text('Waze'),
            onTap: () => Navigator.pop(context, 'waze'),
          ),
        ],
      ),
    ),
  );
  if (app == null) return;
  final ll = '${punto.latitude},${punto.longitude}';
  final url = app == 'waze'
      ? Uri.parse('https://waze.com/ul?ll=$ll&navigate=yes')
      : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$ll');
  try {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication) && context.mounted) {
      avisar(context, 'No se pudo abrir el mapa.', error: true);
    }
  } catch (_) {
    if (context.mounted) avisar(context, 'No se pudo abrir el mapa.', error: true);
  }
}

/// Mapa de la ruta: los clientes numerados en el orden de visita, con color por estado, unidos con una línea en ese
/// orden. Con el seguimiento GPS también el trayecto del día y la posición del vendedor, que se mueve sola mientras el
/// mapa está abierto. Tocar un cliente muestra su ficha.
class MapaRuta extends StatefulWidget {
  const MapaRuta({
    super.key,
    required this.motor,
    required this.ruta,
    required this.jornadaId,
    required this.visitas,
    required this.onAbrir,
  });

  final Motor motor;
  final Ruta ruta;
  final int jornadaId;

  /// En el orden de visita (pendientes primero).
  final List<Map> visitas;
  final void Function(Map visita) onAbrir;

  @override
  State<MapaRuta> createState() => _MapaRutaState();
}

class _MapaRutaState extends State<MapaRuta> {
  /// Cada cuánto se mueve el punto del vendedor mientras el mapa está abierto.
  static const vivoCada = Duration(seconds: 10);

  final _control = MapController();
  LatLng? _yo;
  List<LatLng> _trayecto = const [];
  Timer? _vivo;

  bool get _seguimiento => widget.ruta.seguimiento(widget.jornadaId);

  @override
  void initState() {
    super.initState();
    // Con el seguimiento la app ya tiene permiso de ubicación: el punto se mueve solo desde que se abre el mapa.
    if (_seguimiento) {
      unawaited(_actualizarVivo());
      _iniciarVivo();
    }
  }

  @override
  void dispose() {
    _vivo?.cancel();
    super.dispose();
  }

  void _iniciarVivo() {
    _vivo ??= Timer.periodic(vivoCada, (_) => _actualizarVivo());
  }

  /// Lee la posición y el trayecto guardado; no mueve la cámara (el vendedor puede estar viendo otra parte).
  Future<void> _actualizarVivo() async {
    final motor = widget.motor;
    final p = await motor.ubicador?.actual();
    final trayecto = _seguimiento ? await motor.trayecto(widget.jornadaId) : const [];
    if (!mounted) return;
    setState(() {
      if (p != null) _yo = LatLng(p.lat, p.lon);
      _trayecto = [for (final t in trayecto) LatLng(t.lat, t.lon)];
    });
  }

  Future<void> _centrarEnMi() async {
    final p = await widget.motor.ubicador?.actual();
    if (!mounted) return;
    if (p == null) {
      avisar(context, 'No se pudo leer su ubicación. Revise el GPS y el permiso de ubicación.', error: true);
      return;
    }
    setState(() => _yo = LatLng(p.lat, p.lon));
    _control.move(_yo!, 16);
    _iniciarVivo();
  }

  void _ficha(Map v, int numero) {
    final ruta = widget.ruta;
    final moneda = ruta.moneda(widget.jornadaId);
    final punto = puntoDe(v);
    final debe = ruta.porCobrar(v['id'] as int);
    final pedidos = ((v['pedidos'] as List?) ?? const []).whereType<Map>().toList();
    final ultimo = pedidos.isEmpty ? null : pedidos.last;
    final comercial = '${v['comercial'] ?? ''}'.trim();
    final pendiente = ruta.estado(v) == 'pendiente';
    final abierta = (ruta.jornada(widget.jornadaId)?['jornada'] as Map?)?['state'] == 'abierta';
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$numero. ${comercial.isNotEmpty ? comercial : v['cliente']}',
                key: const ValueKey('ficha_mapa'),
                style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Color(0xFF111111)),
              ),
              if (comercial.isNotEmpty) Text('${v['cliente']}'),
              if ('${v['direccion'] ?? ''}'.isNotEmpty) Text('${v['direccion']}'),
              if ('${v['telefono'] ?? ''}'.isNotEmpty) Text('Tel. ${v['telefono']}'),
              const SizedBox(height: 6),
              Text(
                etiquetasEstado[ruta.estado(v)] ?? ruta.estado(v),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              if (debe > 0) Text('Debe ${moneda(debe)}'),
              if (ultimo != null) Text('Último pedido ${ultimo['name']} · ${moneda(_num(ultimo['total']))}'),
              if (punto == null)
                const Text(
                  'Sin ubicación: fíjela en la ficha del cliente cuando esté en el negocio.',
                  style: TextStyle(color: Color(0xFFB45309)),
                ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (abierta && pendiente && ruta.seguimiento(widget.jornadaId) && !ruta.llegada(v))
                    FilledButton.icon(
                      key: const ValueKey('mapa_llegue'),
                      icon: const Icon(Icons.where_to_vote),
                      label: const Text('Llegué'),
                      onPressed: () {
                        widget.motor.marcarVisita(v['id'] as int, 'llegada');
                        Navigator.pop(context);
                        avisar(this.context, 'Llegada registrada.');
                      },
                    ),
                  if (punto != null)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.directions),
                      label: const Text('Cómo llegar'),
                      onPressed: () => comoLlegar(context, punto),
                    ),
                  OutlinedButton.icon(
                    key: const ValueKey('mapa_ver_cliente'),
                    icon: const Icon(Icons.person),
                    label: const Text('Ver cliente'),
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onAbrir(v);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final teselas = widget.ruta.mapa(widget.jornadaId)['teselas'] as Map? ?? const {};
    final url = '${teselas['url'] ?? ''}'.isNotEmpty
        ? '${teselas['url']}'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
    final siguiente = widget.visitas.where((v) => widget.ruta.estado(v) == 'pendiente').firstOrNull;
    final marcadores = <Marker>[];
    final puntos = <LatLng>[];
    var sinUbicacion = 0;
    for (var i = 0; i < widget.visitas.length; i++) {
      final v = widget.visitas[i];
      final punto = puntoDe(v);
      if (punto == null) {
        sinUbicacion++;
        continue;
      }
      puntos.add(punto);
      final color = colorEstado(widget.ruta.estado(v), siguiente: identical(v, siguiente));
      marcadores.add(
        Marker(
          point: punto,
          width: 36,
          height: 36,
          child: GestureDetector(
            key: ValueKey('pin_${v['id']}'),
            onTap: () => _ficha(v, i + 1),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 4)],
              ),
              child: Text(
                '${i + 1}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ),
      );
    }
    if (_yo != null) {
      marcadores.add(
        Marker(
          point: _yo!,
          width: 22,
          height: 22,
          child: Container(
            decoration: BoxDecoration(
              color: moradoOdai,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
            ),
          ),
        ),
      );
    }
    final camara = puntos.length > 1
        ? CameraFit.bounds(bounds: LatLngBounds.fromPoints(puntos), padding: const EdgeInsets.all(40), maxZoom: 16)
        : null;
    return Stack(
      children: [
        FlutterMap(
          mapController: _control,
          options: MapOptions(
            initialCameraFit: camara,
            initialCenter: puntos.length == 1 ? puntos.first : const LatLng(23.6, -102.5),
            initialZoom: puntos.length == 1 ? 15 : 5,
          ),
          children: [
            TileLayer(
              urlTemplate: url,
              maxZoom: _num(teselas['max_zoom']) > 0 ? _num(teselas['max_zoom']) : 19,
              userAgentPackageName: 'lat.odai.ruta',
            ),
            PolylineLayer(
              polylines: [
                if (puntos.length > 1)
                  Polyline(
                    points: puntos,
                    strokeWidth: 3,
                    color: const Color(0xAA5F6B7A),
                    pattern: StrokePattern.dashed(segments: const [10, 7]),
                  ),
                if (_trayecto.length > 1)
                  Polyline(points: [..._trayecto, ?_yo], strokeWidth: 4, color: moradoOdai.withValues(alpha: 0.75)),
              ],
            ),
            MarkerLayer(markers: marcadores),
            SimpleAttributionWidget(source: Text('${teselas['atribucion'] ?? '© OpenStreetMap'}')),
          ],
        ),
        if (sinUbicacion > 0)
          Positioned(
            left: 12,
            right: 72,
            top: 10,
            child: Material(
              color: Colors.white.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  sinUbicacion == 1
                      ? '1 cliente sin ubicación (está en la lista).'
                      : '$sinUbicacion clientes sin ubicación (están en la lista).',
                  key: const ValueKey('sin_ubicacion'),
                ),
              ),
            ),
          ),
        Positioned(
          right: 12,
          bottom: 28,
          child: FloatingActionButton(
            heroTag: 'mi_ubicacion',
            tooltip: 'Mi ubicación',
            backgroundColor: moradoOdai,
            foregroundColor: Colors.white,
            onPressed: _centrarEnMi,
            child: const Icon(Icons.my_location),
          ),
        ),
      ],
    );
  }
}
