import 'package:flutter/material.dart';

import '../motor.dart';
import '../ruta.dart';
import 'comun.dart';

/// Cobro de facturas del cliente (de cualquier día). Odoo aplica el monto de la más antigua a la más nueva.
class PantallaCobro extends StatefulWidget {
  const PantallaCobro({super.key, required this.motor, required this.jornadaId, required this.visitaId});

  final Motor motor;
  final int jornadaId;
  final int visitaId;

  @override
  State<PantallaCobro> createState() => _PantallaCobroState();
}

class _PantallaCobroState extends State<PantallaCobro> {
  Ruta? _ruta;
  List<Map<String, Object?>> _facturas = const [];
  final _elegidas = <int>{};
  final _monto = TextEditingController();
  final _referencia = TextEditingController();
  int? _diario;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    Ruta.cargar(widget.motor).then((r) {
      if (!mounted) return;
      final diarios = _diariosDe(r);
      setState(() {
        _ruta = r;
        _facturas = r.facturas(widget.visitaId);
        _elegidas.addAll(_facturas.map((f) => f['id'] as int));
        final efectivo = diarios.where((d) => d['efectivo'] == true);
        _diario = efectivo.isNotEmpty ? efectivo.first['id'] as int : diarios.firstOrNull?['id'] as int?;
        _monto.text = _saldo.toStringAsFixed(2);
      });
    });
  }

  @override
  void dispose() {
    _monto.dispose();
    _referencia.dispose();
    super.dispose();
  }

  List<Map> _diariosDe(Ruta r) =>
      ((r.config(widget.jornadaId)['diarios'] as List?) ?? const []).whereType<Map>().toList();

  double get _saldo => _facturas
      .where((f) => _elegidas.contains(f['id']))
      .fold(0.0, (s, f) => s + ((f['saldo'] as num?)?.toDouble() ?? 0));

  Future<void> _guardar() async {
    final ruta = _ruta!;
    final moneda = ruta.moneda(widget.jornadaId);
    final monto = moneda.redondear(double.tryParse(_monto.text.replaceAll(',', '')) ?? 0);
    if (_diario == null) {
      avisar(context, 'No hay formas de cobro configuradas. En Odoo: Ajustes › Venta en ruta › Formas de cobro.', error: true);
      return;
    }
    if (monto <= 0) {
      avisar(context, 'Escriba el monto cobrado.', error: true);
      return;
    }
    if (_facturas.isEmpty && widget.motor.conSenal) {
      avisar(context, 'El cliente no tiene facturas por cobrar.', error: true);
      return;
    }
    final diario = _diariosDe(ruta).firstWhere((d) => d['id'] == _diario);
    if (diario['efectivo'] != true && ruta.config(widget.jornadaId)['a_bordo'] == true && _referencia.text.trim().isEmpty) {
      avisar(context, 'Escriba la referencia de la transferencia.', error: true);
      return;
    }
    final conSenal = widget.motor.conSenal;
    if (monto > _saldo + 0.004) {
      if (conSenal) {
        avisar(context, 'El monto es mayor que el saldo (${moneda(_saldo)}).', error: true);
        return;
      }
      final seguir = await confirmar(context, 'Cobra de más',
          'El cliente debe ${moneda(_saldo)} según el celular. Lo que sobre quedará a favor del cliente y la '
              'oficina lo revisará. ¿Registrar ${moneda(monto)}?',
          si: 'Registrar');
      if (!seguir || !mounted) return;
    }
    setState(() => _guardando = true);
    try {
      await widget.motor.registrar('cobro', {
        'visita_id': widget.visitaId,
        'journal_id': _diario,
        'monto': monto,
        'factura_ids': _elegidas.toList(),
        'referencia': _referencia.text.trim(),
        'sin_senal': !conSenal,
      });
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
    return Scaffold(
      appBar: AppBar(title: const Text('Cobrar')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_facturas.isEmpty) const Text('El cliente no tiene facturas por cobrar en el celular.'),
          for (final f in _facturas)
            CheckboxListTile(
              value: _elegidas.contains(f['id']),
              onChanged: (x) => setState(() {
                x == true ? _elegidas.add(f['id'] as int) : _elegidas.remove(f['id']);
                _monto.text = _saldo.toStringAsFixed(2);
              }),
              title: Text('${f['name']} · ${moneda((f['saldo'] as num?) ?? 0)}'),
              subtitle: Text('Vence ${f['vence']}${f['vencida'] == true ? ' (vencida)' : ''}'),
            ),
          const SizedBox(height: 8),
          Text('Saldo elegido ${moneda(_saldo)}'),
          if (diarios.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('No hay formas de cobro configuradas en Odoo (Ajustes › Venta en ruta).',
                  style: TextStyle(color: Colors.red)),
            ),
          if (diarios.length > 1)
            DropdownButtonFormField<int>(
              initialValue: _diario,
              decoration: const InputDecoration(labelText: 'Forma de pago'),
              items: [for (final d in diarios) DropdownMenuItem(value: d['id'] as int, child: Text('${d['name']}'))],
              onChanged: (x) => setState(() => _diario = x),
            ),
          TextField(
            controller: _monto,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Monto cobrado',
              suffixIcon: TextButton(
                onPressed: () => setState(() => _monto.text = _saldo.toStringAsFixed(2)),
                child: const Text('Todo'),
              ),
            ),
          ),
          if (esTransferencia)
            TextField(controller: _referencia, decoration: const InputDecoration(labelText: 'Referencia de la transferencia')),
          const SizedBox(height: 12),
          BotonGrande(
            icono: Icons.check,
            texto: 'Registrar cobro',
            onPressed: _guardando ? null : _guardar,
          ),
        ],
      ),
    );
  }
}
