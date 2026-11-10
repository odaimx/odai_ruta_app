import 'package:flutter/material.dart';

import '../api.dart';
import '../motor.dart';
import '../ruta.dart';
import 'comun.dart';

/// Datos de contacto del cliente: alta nueva o corrección. Se guarda en el celular y sube al haber señal.
/// Las condiciones de venta (crédito, lista de precios, plazo) no se tocan aquí: son de la oficina.
class PantallaDatosCliente extends StatefulWidget {
  const PantallaDatosCliente({super.key, required this.motor, required this.jornadaId, this.visita});

  final Motor motor;
  final int jornadaId;

  /// La visita que se corrige; null para dar de alta un cliente nuevo.
  final Map? visita;

  @override
  State<PantallaDatosCliente> createState() => _PantallaDatosClienteState();
}

class _PantallaDatosClienteState extends State<PantallaDatosCliente> {
  static const _campos = [
    ('comercial', 'Nombre comercial', TextInputType.text),
    ('telefono', 'Teléfono', TextInputType.phone),
    ('correo', 'Correo', TextInputType.emailAddress),
    ('calle', 'Calle y número', TextInputType.streetAddress),
    ('colonia', 'Colonia', TextInputType.text),
    ('ciudad', 'Ciudad', TextInputType.text),
    ('cp', 'Código postal', TextInputType.number),
  ];

  final _nombre = TextEditingController();
  late final Map<String, TextEditingController> _control = {
    for (final c in _campos) c.$1: TextEditingController(text: '${(widget.visita?['contacto'] as Map?)?[c.$1] ?? ''}'),
  };
  bool _guardando = false;

  bool get _nuevo => widget.visita == null;

  @override
  void dispose() {
    _nombre.dispose();
    for (final c in _control.values) {
      c.dispose();
    }
    super.dispose();
  }

  String _digitos(String texto) {
    final d = texto.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  Future<void> _guardar() async {
    final datos = {for (final e in _control.entries) e.key: e.value.text.trim()};
    if (_nuevo && _nombre.text.trim().length < 3) {
      avisar(context, 'Escriba el nombre del cliente.', error: true);
      return;
    }
    if (datos['cp']!.isNotEmpty && !RegExp(r'^\d{5}$').hasMatch(datos['cp']!)) {
      avisar(context, 'El código postal lleva 5 dígitos.', error: true);
      return;
    }
    if (datos['correo']!.isNotEmpty && !datos['correo']!.contains('@')) {
      avisar(context, 'El correo no es válido.', error: true);
      return;
    }
    final ruta = await Ruta.cargar(widget.motor);
    if (!mounted) return;
    if (_nuevo && _digitos(datos['telefono']!).length == 10) {
      final mismo = ruta
          .visitas(widget.jornadaId)
          .where((v) => _digitos('${v['telefono'] ?? ''}') == _digitos(datos['telefono']!))
          .firstOrNull;
      if (mismo != null) {
        final seguir = await confirmar(context, 'Cliente repetido',
            '${mismo['cliente']} ya tiene ese teléfono en su ruta. ¿Dar de alta otro cliente de todos modos?',
            si: 'Dar de alta');
        if (!seguir || !mounted) return;
      }
    }
    setState(() => _guardando = true);
    try {
      if (_nuevo) {
        final uuid = await widget.motor.registrar('cliente_nuevo', {
          'jornada_id': widget.jornadaId,
          'nombre': _nombre.text.trim(),
          ...datos,
        });
        if (mounted) {
          avisar(context, 'Cliente dado de alta. Se vende de contado; la oficina lo revisa.');
          Navigator.pop(context, Ruta.idProvisional(uuid));
        }
      } else {
        final antes = (widget.visita!['contacto'] as Map?) ?? const {};
        final cambios = {
          for (final e in datos.entries)
            if ('${antes[e.key] ?? ''}' != e.value) e.key: e.value,
        };
        if (cambios.isNotEmpty) {
          await widget.motor.registrar('cliente', {'visita_id': widget.visita!['id'], 'contacto': cambios});
        }
        if (mounted) {
          avisar(context, cambios.isEmpty ? 'Sin cambios.' : 'Datos guardados.');
          Navigator.pop(context);
        }
      }
    } on ApiError catch (e) {
      if (mounted) avisar(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(_nuevo ? 'Cliente nuevo' : 'Datos del cliente')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_nuevo) ...[
            Card(
              color: tema.colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('El cliente nuevo compra de contado y con la lista de precios general. La oficina le '
                    'asigna crédito u otra lista después de revisarlo.'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nombre,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nombre del cliente *', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
          ] else
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('${widget.visita!['cliente']}', style: tema.textTheme.titleMedium),
            ),
          for (final c in _campos)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _control[c.$1],
                keyboardType: c.$3,
                decoration: InputDecoration(labelText: c.$2, border: const OutlineInputBorder()),
              ),
            ),
          if (!_nuevo)
            Text('Crédito, lista de precios y plazo de pago los cambia la oficina.', style: tema.textTheme.bodySmall),
          const SizedBox(height: 8),
          BotonGrande(
            icono: Icons.save,
            texto: _guardando ? 'Guardando...' : (_nuevo ? 'Dar de alta' : 'Guardar'),
            onPressed: _guardando ? null : _guardar,
          ),
          Text('Funciona sin señal: se envía a Odoo en cuanto haya conexión.', style: tema.textTheme.bodySmall),
        ],
      ),
    );
  }
}
