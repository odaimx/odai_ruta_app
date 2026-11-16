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

  /// La visita en Odoo (un cliente nuevo ya enviado deja su id provisional por el real).
  int get _vid => _ruta?.idReal(widget.visitaId) ?? widget.visitaId;

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
      final hecho = await widget.motor.fijarUbicacion(_vid);
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
    if (ruta == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final v = ruta.visita(widget.jornadaId, widget.visitaId);
    if (v == null) {
      // Ya no se queda cargando: por ejemplo, un cliente nuevo que aún no baja de Odoo.
      return Scaffold(
        appBar: AppBar(),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text('No se encontró el cliente en el celular. Toque Actualizar en la lista de clientes.',
                key: ValueKey('cliente_no_encontrado'), textAlign: TextAlign.center, style: TextStyle(fontSize: 17)),
          ),
        ),
      );
    }
    final moneda = ruta.moneda(widget.jornadaId);
    final credito = (v['credito'] as Map?) ?? const {};
    final disponible = credito['disponible_ruta'];
    final enCola = ruta.pedidoEnCola(_vid);
    final porCobrar = ruta.porCobrar(_vid);
    final abierta = (ruta.jornada(widget.jornadaId)?['jornada'] as Map?)?['state'] == 'abierta';
    final estado = ruta.estado(v);
    // Reparto no vende; con bloqueo total solo se le cobra.
    final reparto = ruta.esReparto(widget.jornadaId);
    final sinVenta = ruta.bloqueoTotal(v);
    final vende = !reparto && !sinVenta;
    final motivoCredito = '${credito['mensaje'] ?? ''}'.trim();
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
            if (vende)
              Accion(Icons.add_shopping_cart, 'Levantar pedido',
                  () => _ir(PantallaPedido(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: _vid)),
                  principal: true),
            if (ruta.cobra(widget.jornadaId))
              Accion(Icons.payments, 'Cobrar',
                  () => _ir(PantallaCobro(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: _vid)),
                  principal: !vende),
            if (ruta.seguimiento(widget.jornadaId) && estado == 'pendiente' && !ruta.llegada(v))
              Accion(Icons.where_to_vote, 'Llegué', () async {
                await widget.motor.marcarVisita(_vid, 'llegada');
                if (context.mounted) avisar(context, 'Llegada registrada.');
                _cargar();
              }),
            if (ruta.seguimiento(widget.jornadaId))
              Accion(Icons.add_location_alt, 'Fijar ubicación aquí', _fijarUbicacion),
            if (estado == 'pendiente' && !reparto)
              Accion(Icons.block, 'Sin venta',
                  () => _ir(PantallaSinVenta(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: _vid))),
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
          if (sinVenta)
            Container(
              key: const ValueKey('bloqueo_total'),
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFEBEE),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: rojoOdai),
              ),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.do_not_disturb_on, color: rojoOdai),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('No se le vende: solo cobrar',
                        style: TextStyle(fontWeight: FontWeight.w800, color: rojoOdai)),
                    Text(ruta.motivoBloqueo(v).isEmpty ? 'Sin motivo capturado en Odoo.' : 'Motivo: ${ruta.motivoBloqueo(v)}'),
                  ]),
                ),
              ]),
            ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text('Crédito', style: tema.textTheme.titleSmall),
                  if (credito['estado'] == 'block') ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.credit_card_off, size: 18, color: rojoOdai),
                    const Text(' Bloqueado', style: TextStyle(color: rojoOdai, fontWeight: FontWeight.w700)),
                  ],
                ]),
                Text(credito['a_credito'] == true
                    ? (disponible == null
                        ? 'Sin límite'
                        : 'Para vender ${moneda((disponible as num) - enCola)}')
                    : 'Solo de contado'),
                if ((credito['vencido'] as num? ?? 0) > 0) Text('Vencido ${moneda(credito['vencido'] as num)}'),
                // Por qué no tiene crédito (o por qué está bloqueado).
                if (motivoCredito.isNotEmpty)
                  Text('Motivo: $motivoCredito', key: const ValueKey('motivo_credito'))
                else if (credito['a_credito'] != true)
                  Text(
                    v['alta_ruta'] == true
                        ? 'Motivo: cliente nuevo, de contado hasta que la oficina lo revise.'
                        : 'Motivo: sin crédito autorizado.',
                    key: const ValueKey('motivo_credito'),
                  ),
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
                  // Pedido con devolución (por revisar en la oficina o ya aplicada).
                  subtitle: '${p['devolucion'] ?? ''}'.isEmpty && ruta.devolucionEnCola(_vid, p['id'] as int) == null
                      ? null
                      : Row(key: ValueKey('pedido_devolucion_${p['id']}'), children: [
                          const Icon(Icons.assignment_return, size: 16, color: naranjaOdai),
                          const SizedBox(width: 4),
                          Text(
                            p['devolucion'] == 'devuelto' ? 'Con devolución' : 'Devolución por revisar',
                            style: const TextStyle(color: naranjaOdai, fontWeight: FontWeight.w600),
                          ),
                        ]),
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
                              motor: widget.motor, jornadaId: widget.jornadaId, visitaId: _vid, pedido: p)),
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
