import 'package:flutter/material.dart';

import '../api.dart';
import '../motor.dart';

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


/// Foto del producto guardada en el celular (se ve sin señal). Sin foto todavía, un cuadro gris.
class Miniatura extends StatelessWidget {
  const Miniatura({super.key, required this.motor, required this.productoId, this.lado = 56});

  final Motor motor;
  final int productoId;
  final double lado;

  @override
  Widget build(BuildContext context) {
    final vacio = Container(
      width: lado,
      height: lado,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.inventory_2_outlined, color: Theme.of(context).colorScheme.outline),
    );
    return ListenableBuilder(
      listenable: motor,
      builder: (context, _) => FutureBuilder(
        future: motor.imagen(productoId),
        initialData: motor.imagenEnMemoria(productoId)?.$1,
        builder: (context, foto) => foto.data == null
            ? vacio
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(foto.data!, width: lado, height: lado, fit: BoxFit.contain, gaplessPlayback: true,
                    errorBuilder: (_, _, _) => vacio),
              ),
      ),
    );
  }
}
