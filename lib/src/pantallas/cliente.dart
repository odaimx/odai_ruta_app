import 'package:flutter/material.dart';

import '../motor.dart';
import '../ruta.dart';
import 'cliente_datos.dart';
import 'cobro.dart';
import 'devolucion.dart';
import 'mapa_ruta.dart';
import '../tema.dart';
import 'comun.dart';
import 'pedido.dart';
import 'sin_venta.dart';

/// Ficha del cliente: crédito, lo que debe y qué hacer en la visita.
class PantallaCliente extends StatefulWidget {
  const PantallaCliente({super.key, required this.motor, required this.jornadaId, required this.visitaId});

  final Motor motor;
  final int jornadaId;
  final int visitaId;

  @override
  State<PantallaCliente> createState() => _PantallaClienteState();
}

class _PantallaClienteState extends State<PantallaCliente> {
  Ruta? _ruta;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    final ruta = await Ruta.cargar(widget.motor);
    if (mounted) setState(() => _ruta = ruta);
  }

  Future<void> _ir(Widget pantalla) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
    _cargar();
  }

  /// Guarda la ubicación del cliente donde está el vendedor (si ya tenía una lejos, la aprueba el supervisor).
  Future<void> _fijarUbicacion() async {
    final ok = await confirmar(context, 'Fijar ubicación',
        '¿Está en el negocio del cliente? Se guarda la ubicación del celular como la del cliente.', si: 'Fijar');
    if (!ok || !mounted) return;
    try {
      final hecho = await widget.motor.fijarUbicacion(widget.visitaId);
      if (!mounted) return;
      avisar(
          context,
          hecho
              ? 'Ubicación guardada. Si el cliente ya tenía otra lejos, la revisa el supervisor.'
              : 'No se pudo leer la ubicación. Revise el GPS y el permiso de ubicación.',
          error: !hecho);
    } catch (e) {
      if (mounted) avisar(context, textoError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ruta = _ruta;
    final v = ruta?.visita(widget.jornadaId, widget.visitaId);
    if (ruta == null || v == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final moneda = ruta.moneda(widget.jornadaId);
    final credito = (v['credito'] as Map?) ?? const {};
    final disponible = credito['disponible_ruta'];
    final enCola = ruta.pedidoEnCola(widget.visitaId);
    final porCobrar = ruta.porCobrar(widget.visitaId);
    final abierta = (ruta.jornada(widget.jornadaId)?['jornada'] as Map?)?['state'] == 'abierta';
    final estado = ruta.estado(v);
    final tema = Theme.of(context);
    final pedidos = ((v['pedidos'] as List?) ?? const []).whereType<Map>().toList();
    return Scaffold(
      appBar: CabeceraOdai(
          titulo: widget.motor.nombreVendedor.isEmpty ? '${v['cliente']}' : widget.motor.nombreVendedor,
          subtitulo: '${v['cliente']}'),
      bottomNavigationBar: const PieOdai(),
      body: Column(children: [
        BarraAcciones(motor: widget.motor, acciones: [
          if (abierta) ...[
            Accion(Icons.add_shopping_cart, 'Levantar pedido',
                () => _ir(PantallaPedido(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId)),
                principal: true),
            if (ruta.cobra(widget.jornadaId))
              Accion(Icons.payments, 'Cobrar',
                  () => _ir(PantallaCobro(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId))),
            if (ruta.seguimiento(widget.jornadaId) && estado == 'pendiente' && !ruta.llegada(v))
              Accion(Icons.where_to_vote, 'Llegué', () async {
                await widget.motor.marcarVisita(widget.visitaId, 'llegada');
                if (context.mounted) avisar(context, 'Llegada registrada.');
                _cargar();
              }),
            if (ruta.seguimiento(widget.jornadaId))
              Accion(Icons.add_location_alt, 'Fijar ubicación aquí', _fijarUbicacion),
            if (estado == 'pendiente')
              Accion(Icons.block, 'Sin venta',
                  () => _ir(PantallaSinVenta(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId))),
          ],
          if (puntoDe(v) != null) Accion(Icons.directions, 'Cómo llegar', () => comoLlegar(context, puntoDe(v)!)),
          Accion(Icons.edit, 'Modificar cliente',
              () => _ir(PantallaDatosCliente(motor: widget.motor, jornadaId: widget.jornadaId, visita: v))),
        ]),
        Expanded(
          child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if ((v['comercial'] as String?)?.isNotEmpty == true) Text('${v['comercial']}', style: tema.textTheme.titleMedium),
          if ((v['direccion'] as String?)?.isNotEmpty == true) Text('${v['direccion']}'),
          if ((v['telefono'] as String?)?.isNotEmpty == true) Text('Tel. ${v['telefono']}'),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            Chip(label: Text(etiquetasEstado[estado] ?? estado)),
            if (v['alta_ruta'] == true) const Chip(label: Text('Nuevo · de contado')),
            if ((v['id'] as int) < 0) const Chip(label: Text('Por enviar')),
          ]),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Crédito', style: tema.textTheme.titleSmall),
                Text(credito['a_credito'] == true
                    ? (disponible == null
                        ? 'Sin límite'
                        : 'Para vender ${moneda((disponible as num) - enCola)}')
                    : 'Solo de contado'),
                if ((credito['vencido'] as num? ?? 0) > 0) Text('Vencido ${moneda(credito['vencido'] as num)}'),
                if ((credito['mensaje'] as String?)?.isNotEmpty == true) Text('${credito['mensaje']}'),
                Text('Por cobrar ${moneda(porCobrar)}'),
              ]),
            ),
          ),
          if (pedidos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Pedidos', style: tema.textTheme.titleSmall),
            // Cada pedido en su marco: abierto queda resaltado (borde morado y fondo lavanda) con sus productos
            // adentro, para no confundirlo con los demás.
            for (final p in pedidos)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ExpansionTile(
                  key: ValueKey('pedido_${p['id']}'),
                  shape: RoundedRectangleBorder(
                      side: const BorderSide(color: moradoOdai, width: 2), borderRadius: BorderRadius.circular(12)),
                  collapsedShape: RoundedRectangleBorder(
                      side: const BorderSide(color: bordeMorado), borderRadius: BorderRadius.circular(12)),
                  backgroundColor: lavanda,
                  collapsedBackgroundColor: Colors.white,
                  clipBehavior: Clip.antiAlias,
                  title: Text('${p['name']} · ${moneda(p['total'] as num? ?? 0)}',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF111111))),
                  childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  children: [
                    for (final l in ((p['lineas'] as List?) ?? const []).whereType<Map>())
                      Container(
                        margin: const EdgeInsets.only(top: 4),
                        decoration:
                            BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                        child: ListTile(
                            dense: true,
                            title: Text('${l['producto']}'),
                            trailing: Text('${l['cantidad']} ${l['uom']}')),
                      ),
                    if (abierta && p['state'] == 'sale')
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          key: ValueKey('devolver_${p['id']}'),
                          icon: const Icon(Icons.assignment_return),
                          label: const Text('Devolver'),
                          onPressed: () => _ir(PantallaDevolucion(
                              motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId, pedido: p)),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ],
      ),
        ),
      ]),
    );
  }
}
