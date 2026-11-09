import 'package:flutter/material.dart';

import '../motor.dart';
import '../ruta.dart';
import 'comun.dart';

/// Visita sin venta, con su motivo.
class PantallaSinVenta extends StatefulWidget {
  const PantallaSinVenta({super.key, required this.motor, required this.jornadaId, required this.visitaId});

  final Motor motor;
  final int jornadaId;
  final int visitaId;

  @override
  State<PantallaSinVenta> createState() => _PantallaSinVentaState();
}

class _PantallaSinVentaState extends State<PantallaSinVenta> {
  List<Map> _motivos = const [];
  int? _motivo;
  final _nota = TextEditingController();
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    Ruta.cargar(widget.motor).then((r) {
      final deJornada = ((r.jornada(widget.jornadaId)?['motivos'] as List?) ?? const []).whereType<Map>().toList();
      if (mounted) setState(() => _motivos = deJornada.isNotEmpty ? deJornada : r.motivos);
    });
  }

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    setState(() => _guardando = true);
    try {
      await widget.motor.registrar('sin_venta', {'visita_id': widget.visitaId, 'motivo_id': _motivo, 'nota': _nota.text.trim()});
      if (mounted) {
        avisar(context, 'Visita sin venta guardada.');
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
    return Scaffold(
      appBar: AppBar(title: const Text('Sin venta')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          RadioGroup<int>(
            groupValue: _motivo,
            onChanged: (v) => setState(() => _motivo = v),
            child: Column(children: [
              for (final m in _motivos) RadioListTile<int>(value: m['id'] as int, title: Text('${m['name']}')),
            ]),
          ),
          TextField(controller: _nota, decoration: const InputDecoration(labelText: 'Nota (opcional)'), maxLines: 2),
          const SizedBox(height: 12),
          BotonGrande(icono: Icons.check, texto: 'Guardar', onPressed: _motivo == null || _guardando ? null : _guardar),
        ],
      ),
    );
  }
}
