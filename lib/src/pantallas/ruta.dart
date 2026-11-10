import 'package:flutter/material.dart';

import '../motor.dart';
import '../ruta.dart';
import 'cliente.dart';
import 'comun.dart';

/// Los clientes de la jornada: primero los que faltan por visitar.
class PantallaRuta extends StatefulWidget {
  const PantallaRuta({super.key, required this.motor, required this.jornadaId});

  final Motor motor;
  final int jornadaId;

  @override
  State<PantallaRuta> createState() => _PantallaRutaState();
}

class _PantallaRutaState extends State<PantallaRuta> {
  Ruta? _ruta;
  String _filtro = '';

  @override
  void initState() {
    super.initState();
    widget.motor.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    widget.motor.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    final ruta = await Ruta.cargar(widget.motor);
    if (mounted) setState(() => _ruta = ruta);
  }

  Future<void> _cerrar() async {
    final ruta = _ruta!;
    final pendientes = ruta.visitas(widget.jornadaId).where((v) => ruta.estado(v) == 'pendiente').length;
    if (pendientes > 0 && ruta.config(widget.jornadaId)['cerrar_pendientes'] != true) {
      avisar(context, 'Faltan $pendientes clientes. Levante el pedido o indique el motivo de no venta.', error: true);
      return;
    }
    final ok = await confirmar(
        context,
        'Cerrar jornada',
        pendientes > 0
            ? 'Quedan $pendientes clientes sin visitar; se marcarán como no visitados. Después ya no podrá vender '
                'en esta jornada.'
            : 'Después ya no podrá vender en esta jornada.',
        si: 'Cerrar');
    if (!ok || !mounted) return;
    try {
      await widget.motor.registrar('cerrar', {'jornada_id': widget.jornadaId});
      if (mounted) {
        avisar(context, 'Cierre guardado. Se enviará a Odoo con lo demás.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) avisar(context, textoError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ruta = _ruta;
    final datos = ruta?.jornada(widget.jornadaId);
    if (ruta == null || datos == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final jornada = datos['jornada'] as Map;
    final moneda = ruta.moneda(widget.jornadaId);
    final t = _filtro.toLowerCase();
    final visitas = ruta
        .visitas(widget.jornadaId)
        .where((v) => t.isEmpty || '${v['cliente']} ${v['comercial']} ${(v['codigos'] as List?)?.join(' ')}'.toLowerCase().contains(t))
        .toList();
    final aviso = datos['licencia_aviso'] as String?;
    return Scaffold(
      appBar: AppBar(title: Text('${jornada['ruta']}'), actions: [
        IconButton(
          tooltip: 'Sincronizar',
          onPressed: widget.motor.sincronizando ? null : () => widget.motor.sincronizar(),
          icon: const Icon(Icons.sync),
        ),
      ]),
      body: Column(
        children: [
          if (aviso != null && aviso.isNotEmpty)
            MaterialBanner(content: Text(aviso), actions: const [SizedBox.shrink()]),
          _PanelTablero(tablero: ruta.tablero(widget.jornadaId), moneda: moneda),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar cliente', border: OutlineInputBorder()),
              onChanged: (v) => setState(() => _filtro = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: visitas.length,
              itemBuilder: (context, i) {
                final v = visitas[i];
                final estado = ruta.estado(v);
                final porCobrar = ruta.porCobrar(v['id'] as int);
                return ListTile(
                  leading: CircleAvatar(child: Text('${v['secuencia'] ?? i + 1}')),
                  title: Text('${(v['comercial'] as String?)?.isNotEmpty == true ? v['comercial'] : v['cliente']}'),
                  subtitle: Text([
                    etiquetasEstado[estado] ?? estado,
                    if (ruta.enCola(v)) 'por enviar',
                    if (porCobrar > 0) 'debe ${moneda(porCobrar)}',
                  ].join(' · ')),
                  trailing: Icon(estado == 'pendiente'
                      ? Icons.chevron_right
                      : estado == 'pedido'
                          ? Icons.shopping_cart
                          : Icons.block),
                  onTap: () async {
                    await Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => PantallaCliente(
                                motor: widget.motor, jornadaId: widget.jornadaId, visitaId: v['id'] as int)));
                    _cargar();
                  },
                );
              },
            ),
          ),
          if (jornada['state'] == 'abierta')
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: BotonGrande(icono: Icons.flag, texto: 'Cerrar jornada', tono: true, onPressed: _cerrar),
              ),
            ),
        ],
      ),
    );
  }
}


class _PanelTablero extends StatelessWidget {
  const _PanelTablero({required this.tablero, required this.moneda});

  final Tablero tablero;
  final Moneda moneda;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    Widget dato(String titulo, String valor, {String? pie}) => Expanded(
          child: Column(children: [
            Text(titulo, style: tema.textTheme.labelMedium),
            FittedBox(child: Text(valor, style: tema.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold))),
            if (pie != null) Text(pie, style: tema.textTheme.bodySmall),
          ]),
        );
    final avance = tablero.visitas == 0 ? 0.0 : tablero.hechas / tablero.visitas;
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      color: tema.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(children: [
          Row(children: [
            dato('Vendido', moneda(tablero.vendido)),
            dato('Cobrado', moneda(tablero.cobrado)),
            dato('Visitas', '${tablero.hechas}/${tablero.visitas}',
                pie: '${tablero.conPedido} con pedido · ${tablero.sinVenta} sin venta'),
          ]),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: avance, minHeight: 6, borderRadius: BorderRadius.circular(3)),
          const SizedBox(height: 4),
          Text(tablero.pendientes == 0 ? 'Ruta completa' : '${tablero.pendientes} por visitar',
              style: tema.textTheme.bodySmall),
        ]),
      ),
    );
  }
}
