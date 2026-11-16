import 'package:flutter/material.dart';

import '../motor.dart';
import '../ruta.dart';
import '../tema.dart';
import 'comun.dart';

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;

String _cantidad(double c) => c == c.roundToDouble() ? c.toStringAsFixed(0) : c.toStringAsFixed(2);

/// Devolución de un pedido: qué productos y cuántos regresan, con su motivo. Si es de contado en efectivo o a
/// crédito, de esta jornada y sin factura, Odoo la aplica sola (regresa el producto y el efectivo); si no, la
/// revisa la oficina.
class PantallaDevolucion extends StatefulWidget {
  const PantallaDevolucion({
    super.key,
    required this.motor,
    required this.jornadaId,
    required this.visitaId,
    required this.pedido,
  });

  final Motor motor;
  final int jornadaId;
  final int visitaId;
  final Map pedido;

  @override
  State<PantallaDevolucion> createState() => _PantallaDevolucionState();
}

class _PantallaDevolucionState extends State<PantallaDevolucion> {
  Ruta? _ruta;
  final Map<int, double> _cantidades = {};
  bool _todo = false;
  int? _motivo;
  final _nota = TextEditingController();
  bool _guardando = false;

  List<Map> get _lineas => ((widget.pedido['lineas'] as List?) ?? const [])
      .whereType<Map>()
      .where((l) => l['de_combo'] != true && l['id'] is int && _num(l['cantidad']) > 0)
      .toList();

  String get _oficina => '${widget.pedido['devolucion_oficina'] ?? ''}'.trim();

  @override
  void initState() {
    super.initState();
    Ruta.cargar(widget.motor).then((r) {
      if (mounted) setState(() => _ruta = r);
    });
  }

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  double _cuanto(Map l) => _todo ? _num(l['cantidad']) : (_cantidades[l['id']] ?? 0);

  double get _monto => _lineas.fold(0.0, (s, l) => s + _cuanto(l) * _num(l['precio']));

  bool get _hayAlgo => _lineas.any((l) => _cuanto(l) > 0);

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await widget.motor.registrar('devolucion', {
        'visita_id': widget.visitaId,
        'pedido_id': widget.pedido['id'],
        'todo': _todo,
        'lineas': [
          for (final l in _lineas)
            if (_cuanto(l) > 0) {'linea_id': l['id'], 'cantidad': _cuanto(l)},
        ],
        'motivo_id': _motivo,
        'nota': _nota.text.trim(),
        // Solo para el celular: el tablero resta lo que se aplica solo mientras espera en la cola.
        'monto': _monto,
        'oficina': _oficina.isNotEmpty,
      });
      if (mounted) {
        avisar(context, _oficina.isEmpty ? 'Devolución guardada.' : 'Devolución enviada a la oficina para revisión.');
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
    if (ruta == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final moneda = ruta.moneda(widget.jornadaId);
    final motivos = ruta.motivosDevolucion(widget.jornadaId);
    final enCola = ruta.devolucionEnCola(widget.visitaId, widget.pedido['id'] as int) != null;
    return Scaffold(
      appBar: CabeceraOdai(titulo: 'Devolución', subtitulo: '${widget.pedido['name']}'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_oficina.isNotEmpty)
            TarjetaOdai(
              child: Text(
                'La revisa la oficina: $_oficina',
                key: const ValueKey('devolucion_oficina'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          if (enCola)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Ya hay una devolución de este pedido esperando enviarse.',
                style: TextStyle(fontWeight: FontWeight.w600, color: moradoOscuro),
              ),
            ),
          SwitchListTile(
            key: const ValueKey('devolver_todo'),
            title: const Text('Devuelve todo el pedido'),
            value: _todo,
            onChanged: (v) => setState(() => _todo = v),
          ),
          for (final l in _lineas)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${l['producto']}', style: const TextStyle(fontSize: 16)),
                        Text(
                          'Pidió ${_cantidad(_num(l['cantidad']))} ${l['uom']} · ${moneda(_num(l['precio']))}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    key: ValueKey('dev_menos_${l['id']}'),
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: _todo
                        ? null
                        : () => setState(() {
                            final c = _cantidades[l['id']] ?? 0;
                            _cantidades[l['id'] as int] = c >= 1 ? c - 1 : 0;
                          }),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      _cantidad(_cuanto(l)),
                      key: ValueKey('dev_cantidad_${l['id']}'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    key: ValueKey('dev_mas_${l['id']}'),
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: _todo
                        ? null
                        : () => setState(() {
                            final c = _cantidades[l['id']] ?? 0;
                            final max = _num(l['cantidad']);
                            _cantidades[l['id'] as int] = c + 1 > max ? max : c + 1;
                          }),
                  ),
                ],
              ),
            ),
          const Divider(),
          Text('Devuelve ${moneda(_monto)}', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Text('Motivo', style: Theme.of(context).textTheme.titleSmall),
          if (motivos.isEmpty)
            const Text('No bajaron motivos de devolución. Sincronice.')
          else
            RadioGroup<int>(
              groupValue: _motivo,
              onChanged: (v) => setState(() => _motivo = v),
              child: Column(
                children: [
                  for (final m in motivos) RadioListTile<int>(value: m['id'] as int, title: Text('${m['name']}')),
                ],
              ),
            ),
          TextField(
            controller: _nota,
            decoration: const InputDecoration(labelText: 'Nota (opcional)'),
            maxLines: 2,
          ),
          const SizedBox(height: 12),
          BotonGrande(
            icono: Icons.assignment_return,
            texto: _oficina.isEmpty ? 'Devolver' : 'Enviar a la oficina',
            onPressed: !_hayAlgo || _motivo == null || _guardando || enCola ? null : _guardar,
          ),
        ],
      ),
    );
  }
}
