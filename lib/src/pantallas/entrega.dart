import 'package:flutter/material.dart';

import '../motor.dart';
import '../ruta.dart';
import '../tema.dart';
import 'cliente.dart';
import 'cobro.dart';
import 'comun.dart';

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;

String _cantidad(double c) => c == c.roundToDouble() ? c.toStringAsFixed(0) : c.toStringAsFixed(2);

/// Reparto: el chofer entrega los pedidos del cliente (todo, una parte o nada) y cobra los de contado.
class PantallaEntrega extends StatefulWidget {
  const PantallaEntrega({super.key, required this.motor, required this.jornadaId, required this.visitaId});

  final Motor motor;
  final int jornadaId;
  final int visitaId;

  @override
  State<PantallaEntrega> createState() => _PantallaEntregaState();
}

class _PantallaEntregaState extends State<PantallaEntrega> {
  Ruta? _ruta;

  /// Cantidad que se entrega de cada producto (por ``move_id``); empieza con todo lo del pedido.
  final _cantidades = <int, double>{};
  bool _guardando = false;

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
    if (!mounted) return;
    final visita = ruta.visita(widget.jornadaId, widget.visitaId);
    setState(() {
      _ruta = ruta;
      for (final e in visita == null ? const <Map>[] : ruta.entregas(visita)) {
        for (final l in ((e['lineas'] as List?) ?? const []).whereType<Map>()) {
          _cantidades.putIfAbsent(l['move_id'] as int, () => _num(l['cantidad']));
        }
      }
    });
  }

  bool _completa(List<Map> entregas) => entregas.every((e) => ((e['lineas'] as List?) ?? const [])
      .whereType<Map>()
      .every((l) => (_cantidades[l['move_id']] ?? 0) + 1e-6 >= _num(l['cantidad'])));

  bool _nada(List<Map> entregas) => entregas.every(
      (e) => ((e['lineas'] as List?) ?? const []).whereType<Map>().every((l) => (_cantidades[l['move_id']] ?? 0) <= 0));

  Future<void> _entregar(List<Map> entregas) async {
    if (_nada(entregas)) {
      avisar(context, 'No marcó nada para entregar. Si el cliente no recibió, use "No entregado".', error: true);
      return;
    }
    final completa = _completa(entregas);
    if (!completa) {
      final ok = await confirmar(context, 'Entrega en parte',
          'Lo que no entrega regresa al almacén y el pedido baja a lo entregado. ¿Registrar la entrega?',
          si: 'Registrar');
      if (!ok || !mounted) return;
    }
    await _registrar({
      'resultado': completa ? 'completa' : 'parcial',
      if (!completa)
        'lineas': [
          for (final e in entregas)
            for (final l in ((e['lineas'] as List?) ?? const []).whereType<Map>())
              {'move_id': l['move_id'], 'cantidad': _cantidades[l['move_id']] ?? 0},
        ],
    }, completa ? 'Entrega guardada.' : 'Entrega en parte guardada.');
    if (!mounted) return;
    // Pedidos de contado: se cobran en seguida (puede saltarse con atrás).
    final ruta = await Ruta.cargar(widget.motor);
    final visita = ruta.visita(widget.jornadaId, widget.visitaId);
    if (visita == null || !mounted) return;
    for (final e in ruta.entregas(visita)) {
      final falta = ruta.porCobrarEntrega(widget.visitaId, e);
      if (falta <= 0.004 || !mounted) continue;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => PantallaCobroEntrega(
                  motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId, entrega: e, monto: falta)));
    }
  }

  Future<void> _noEntregado() async {
    final ruta = _ruta!;
    final deJornada = ((ruta.jornada(widget.jornadaId)?['motivos'] as List?) ?? const []).whereType<Map>().toList();
    final motivos = deJornada.isNotEmpty ? deJornada : ruta.motivos;
    final nota = TextEditingController();
    int? motivo;
    final elegido = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogo) => AlertDialog(
          title: const Text('No entregado'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              RadioGroup<int>(
                groupValue: motivo,
                onChanged: (v) => setDialogo(() => motivo = v),
                child: Column(children: [
                  for (final m in motivos) RadioListTile<int>(value: m['id'] as int, title: Text('${m['name']}')),
                ]),
              ),
              TextField(controller: nota, decoration: const InputDecoration(labelText: 'Nota (opcional)')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
            FilledButton(
                onPressed: motivo == null ? null : () => Navigator.pop(context, motivo), child: const Text('Guardar')),
          ],
        ),
      ),
    );
    final texto = nota.text.trim();
    nota.dispose();
    if (elegido == null || !mounted) return;
    await _registrar({'resultado': 'no', 'motivo_id': elegido, 'nota': texto},
        'Quedó como no entregado; sale en el siguiente reparto.');
  }

  Future<void> _registrar(Map<String, Object?> datos, String listo) async {
    setState(() => _guardando = true);
    try {
      await widget.motor.registrar('entrega', {'visita_id': widget.visitaId, ...datos});
      if (mounted) avisar(context, listo);
    } catch (e) {
      if (mounted) avisar(context, textoError(e), error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ruta = _ruta;
    final visita = ruta?.visita(widget.jornadaId, widget.visitaId);
    if (ruta == null || visita == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final moneda = ruta.moneda(widget.jornadaId);
    final entregas = ruta.entregas(visita);
    final estado = ruta.estado(visita);
    final pendiente = estado == 'pendiente';
    final abierta = (ruta.jornada(widget.jornadaId)?['jornada'] as Map?)?['state'] == 'abierta';
    final porCobrar = ruta.porCobrar(widget.visitaId);
    final comercial = '${visita['comercial'] ?? ''}'.trim();
    final total = entregas.fold(0.0, (s, e) => s + Ruta.valorEntregado(e, _cantidades));
    return Scaffold(
      appBar: CabeceraOdai(
          titulo: comercial.isNotEmpty ? comercial : '${visita['cliente']}', subtitulo: '${visita['direccion'] ?? ''}'),
      bottomNavigationBar: const PieOdai(),
      body: Column(children: [
        BarraAcciones(motor: widget.motor, acciones: [
          Accion(Icons.person, 'Ver ficha', () async {
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) =>
                        PantallaCliente(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId)));
            _cargar();
          }),
          if (abierta && porCobrar > 0)
            Accion(Icons.payments, 'Cobrar notas ${moneda(porCobrar)}', () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          PantallaCobro(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId)));
              _cargar();
            }),
        ]),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            children: [
              if (!pendiente)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(etiquetasEstado[estado] ?? estado,
                      key: const ValueKey('estado_entrega'),
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: moradoOscuro)),
                ),
              if (entregas.isEmpty) const Text('Este cliente no tiene entregas en el celular. Sincronice.'),
              for (final e in entregas) _tarjeta(ruta, e, moneda, pendiente && abierta),
            ],
          ),
        ),
        if (abierta && pendiente && entregas.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(children: [
              BotonGrande(
                  key: const ValueKey('entregar'),
                  icono: Icons.local_shipping,
                  texto: _completa(entregas) ? 'Entregar todo · ${moneda(total)}' : 'Entregar así · ${moneda(total)}',
                  onPressed: _guardando ? null : () => _entregar(entregas)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const ValueKey('no_entregado'),
                  icon: const Icon(Icons.block),
                  label: const Text('No entregado'),
                  onPressed: _guardando ? null : _noEntregado,
                ),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _tarjeta(Ruta ruta, Map e, Moneda moneda, bool editable) {
    final falta = ruta.porCobrarEntrega(widget.visitaId, e);
    final lineas = ((e['lineas'] as List?) ?? const []).whereType<Map>().toList();
    final nota = '${e['nota'] ?? ''}'.trim();
    return TarjetaOdai(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
              child: Text('${e['pedido']}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF111111)))),
          Text(e['contado'] == true ? 'Contado' : 'Crédito',
              style: TextStyle(fontWeight: FontWeight.w600, color: e['contado'] == true ? verdeOdai : moradoOscuro)),
        ]),
        if (nota.isNotEmpty) Text(nota, style: const TextStyle(fontStyle: FontStyle.italic)),
        const Divider(),
        for (final l in lineas)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${l['producto']}', style: const TextStyle(fontSize: 16)),
                  Text('Pidió ${_cantidad(_num(l['cantidad']))} ${l['uom']} · ${moneda(_num(l['precio']))}',
                      style: Theme.of(context).textTheme.bodySmall),
                ]),
              ),
              if (editable) ...[
                IconButton(
                  key: ValueKey('menos_${l['move_id']}'),
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => setState(() {
                    final c = _cantidades[l['move_id']] ?? 0;
                    _cantidades[l['move_id'] as int] = c >= 1 ? c - 1 : 0;
                  }),
                ),
                SizedBox(
                  width: 40,
                  child: Text(_cantidad(_cantidades[l['move_id']] ?? 0),
                      key: ValueKey('cantidad_${l['move_id']}'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => setState(() {
                    final c = _cantidades[l['move_id']] ?? 0;
                    final max = _num(l['cantidad']);
                    _cantidades[l['move_id'] as int] = c + 1 > max ? max : c + 1;
                  }),
                ),
              ] else
                Text('${_cantidad(_num(l['cantidad']))} ${l['uom']}'),
            ]),
          ),
        if (falta > 0.004) ...[
          const Divider(),
          Row(children: [
            Expanded(child: Text('Por cobrar ${moneda(falta)}', style: const TextStyle(fontWeight: FontWeight.w700))),
            if (!editable && (ruta.jornada(widget.jornadaId)?['jornada'] as Map?)?['state'] == 'abierta' &&
                ruta.estado(ruta.visita(widget.jornadaId, widget.visitaId)!) != 'no_entregado')
              FilledButton.icon(
                icon: const Icon(Icons.payments),
                label: const Text('Cobrar'),
                onPressed: () async {
                  await Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => PantallaCobroEntrega(
                              motor: widget.motor,
                              jornadaId: widget.jornadaId,
                              visitaId: widget.visitaId,
                              entrega: e,
                              monto: falta)));
                  _cargar();
                },
              ),
          ]),
        ],
      ]),
    );
  }
}

/// Cobro de un pedido de contado al entregarlo: si ya está facturado se aplica a su factura; si no, queda como
/// pago del pedido. Entra a la liquidación del chofer.
class PantallaCobroEntrega extends StatefulWidget {
  const PantallaCobroEntrega(
      {super.key,
      required this.motor,
      required this.jornadaId,
      required this.visitaId,
      required this.entrega,
      required this.monto});

  final Motor motor;
  final int jornadaId;
  final int visitaId;
  final Map entrega;
  final double monto;

  @override
  State<PantallaCobroEntrega> createState() => _PantallaCobroEntregaState();
}

class _PantallaCobroEntregaState extends State<PantallaCobroEntrega> {
  Ruta? _ruta;
  int? _diario;
  final _monto = TextEditingController();
  final _recibido = TextEditingController();
  final _referencia = TextEditingController();
  final _manual = FocusNode();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _monto.text = widget.monto.toStringAsFixed(2);
    Ruta.cargar(widget.motor).then((r) {
      if (!mounted) return;
      final diarios = _diariosDe(r);
      final efectivo = diarios.where((d) => d['efectivo'] == true);
      setState(() {
        _ruta = r;
        _diario = efectivo.isNotEmpty ? efectivo.first['id'] as int : diarios.firstOrNull?['id'] as int?;
      });
    });
  }

  @override
  void dispose() {
    _monto.dispose();
    _recibido.dispose();
    _referencia.dispose();
    _manual.dispose();
    super.dispose();
  }

  List<Map> _diariosDe(Ruta r) => ((r.config(widget.jornadaId)['diarios'] as List?) ?? const []).whereType<Map>().toList();

  double get _montoEscrito => double.tryParse(_monto.text.replaceAll(',', '')) ?? 0;

  Future<void> _guardar() async {
    final ruta = _ruta!;
    final moneda = ruta.moneda(widget.jornadaId);
    final monto = moneda.redondear(_montoEscrito);
    if (_diario == null) {
      avisar(context, 'No hay formas de cobro configuradas. En Odoo: Ajustes › Venta en ruta › Formas de cobro.',
          error: true);
      return;
    }
    if (monto <= 0) {
      avisar(context, 'Escriba el monto cobrado.', error: true);
      return;
    }
    if (monto > widget.monto + 0.004) {
      avisar(context, 'El monto es mayor que lo que falta por cobrar (${moneda(widget.monto)}).', error: true);
      return;
    }
    final diario = _diariosDe(ruta).firstWhere((d) => d['id'] == _diario);
    if (diario['efectivo'] != true && _referencia.text.trim().isEmpty) {
      avisar(context, 'Escriba la referencia de la transferencia.', error: true);
      return;
    }
    final facturas = ((widget.entrega['facturas'] as List?) ?? const []).toList();
    setState(() => _guardando = true);
    try {
      final comun = {
        'visita_id': widget.visitaId,
        'journal_id': _diario,
        'monto': monto,
        'referencia': _referencia.text.trim(),
        'sin_senal': !widget.motor.conSenal,
      };
      if (facturas.isNotEmpty) {
        await widget.motor.registrar('cobro', {...comun, 'factura_ids': facturas});
      } else {
        await widget.motor.registrar('anticipo', {...comun, 'pedido_id': widget.entrega['pedido_id']});
      }
      if (mounted) {
        avisar(context, 'Cobro de ${moneda(monto)} guardado.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _guardando = false);
        avisar(context, textoError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ruta = _ruta;
    if (ruta == null) return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    final moneda = ruta.moneda(widget.jornadaId);
    final diarios = _diariosDe(ruta);
    final esTransferencia = diarios.where((d) => d['id'] == _diario).firstOrNull?['efectivo'] == false;
    final recibido = double.tryParse(_recibido.text.replaceAll(',', '')) ?? 0;
    return Scaffold(
      appBar: CabeceraOdai(titulo: 'Cobrar ${widget.entrega['pedido']}'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Por cobrar ${moneda(widget.monto)}',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: moradoOscuro)),
          if (diarios.length > 1) ...[
            const SizedBox(height: 16),
            DropdownButtonFormField<int>(
              initialValue: _diario,
              decoration: const InputDecoration(labelText: 'Forma de pago'),
              items: [for (final d in diarios) DropdownMenuItem(value: d['id'] as int, child: Text('${d['name']}'))],
              onChanged: (x) => setState(() => _diario = x),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            key: const ValueKey('monto_entrega'),
            controller: _monto,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Monto cobrado'),
          ),
          if (esTransferencia) ...[
            const SizedBox(height: 16),
            TextField(
                controller: _referencia, decoration: const InputDecoration(labelText: 'Referencia de la transferencia')),
          ] else if (_montoEscrito > 0) ...[
            const SizedBox(height: 16),
            const Text('¿Con cuánto paga?'),
            const SizedBox(height: 8),
            MontosRapidos(
              total: _montoEscrito,
              moneda: moneda.call,
              onElegir: (m) => setState(() => _recibido.text = m.toStringAsFixed(2)),
              onManual: () => setState(() {
                _recibido.clear();
                _manual.requestFocus();
              }),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _recibido,
              focusNode: _manual,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Recibido (para el cambio)'),
              onChanged: (_) => setState(() {}),
            ),
            if (recibido > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                    recibido >= _montoEscrito
                        ? 'Cambio ${moneda(recibido - _montoEscrito)}'
                        : 'Faltan ${moneda(_montoEscrito - recibido)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
              ),
          ],
          const SizedBox(height: 16),
          BotonGrande(
              key: const ValueKey('registrar_cobro_entrega'),
              icono: Icons.check,
              texto: 'Registrar cobro',
              onPressed: _guardando ? null : _guardar),
        ],
      ),
    );
  }
}
