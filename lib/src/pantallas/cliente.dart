import 'package:flutter/material.dart';

import '../motor.dart';
import '../ruta.dart';
import 'cobro.dart';
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
      appBar: AppBar(title: Text('${v['cliente']}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if ((v['comercial'] as String?)?.isNotEmpty == true) Text('${v['comercial']}', style: tema.textTheme.titleMedium),
          if ((v['direccion'] as String?)?.isNotEmpty == true) Text('${v['direccion']}'),
          if ((v['telefono'] as String?)?.isNotEmpty == true) Text('Tel. ${v['telefono']}'),
          const SizedBox(height: 8),
          Chip(label: Text(etiquetasEstado[estado] ?? estado)),
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
          if (abierta) ...[
            BotonGrande(
              icono: Icons.add_shopping_cart,
              texto: 'Levantar pedido',
              onPressed: () => _ir(PantallaPedido(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId)),
            ),
            BotonGrande(
              icono: Icons.payments,
              texto: 'Cobrar',
              tono: true,
              onPressed: () => _ir(PantallaCobro(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId)),
            ),
            if (estado == 'pendiente')
              BotonGrande(
                icono: Icons.block,
                texto: 'Sin venta',
                tono: true,
                onPressed: () => _ir(PantallaSinVenta(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId)),
              ),
          ],
          if (pedidos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Pedidos', style: tema.textTheme.titleSmall),
            for (final p in pedidos)
              ExpansionTile(
                title: Text('${p['name']} · ${moneda(p['total'] as num? ?? 0)}'),
                children: [
                  for (final l in ((p['lineas'] as List?) ?? const []).whereType<Map>())
                    ListTile(dense: true, title: Text('${l['producto']}'), trailing: Text('${l['cantidad']} ${l['uom']}')),
                ],
              ),
          ],
        ],
      ),
    );
  }
}
