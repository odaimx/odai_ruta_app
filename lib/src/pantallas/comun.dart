import 'package:flutter/material.dart';

import '../api.dart';

/// Muestra el resultado de guardar algo en la cola.
void avisar(BuildContext context, String texto, {bool error = false}) {
  final tema = Theme.of(context);
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(texto),
    backgroundColor: error ? tema.colorScheme.error : null,
    behavior: SnackBarBehavior.floating,
  ));
}

String textoError(Object e) => e is ApiError ? e.mensaje : '$e';

Future<bool> confirmar(BuildContext context, String titulo, String texto, {String si = 'Sí'}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titulo),
      content: Text(texto),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(si)),
      ],
    ),
  );
  return r ?? false;
}

class BotonGrande extends StatelessWidget {
  const BotonGrande({super.key, required this.icono, required this.texto, this.onPressed, this.tono = false});

  final IconData icono;
  final String texto;
  final VoidCallback? onPressed;
  final bool tono;

  @override
  Widget build(BuildContext context) {
    final estilo = FilledButton.styleFrom(minimumSize: const Size.fromHeight(56));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: tono
          ? FilledButton.tonalIcon(onPressed: onPressed, icon: Icon(icono), label: Text(texto), style: estilo)
          : FilledButton.icon(onPressed: onPressed, icon: Icon(icono), label: Text(texto), style: estilo),
    );
  }
}

const etiquetasEstado = {
  'pendiente': 'Por visitar',
  'pedido': 'Con pedido',
  'sin_venta': 'Sin venta',
  'no_visitado': 'No visitado',
};
