import 'package:flutter/material.dart';

import '../api.dart';
import '../motor.dart';
import '../version.dart';

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
    final vacio = Icon(Icons.inventory_2_outlined, color: Colors.grey.shade400);
    Widget marco(Widget hijo) => Container(
          width: lado,
          height: lado,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: ClipRRect(borderRadius: BorderRadius.circular(7), child: Center(child: hijo)),
        );
    return ListenableBuilder(
      listenable: motor,
      builder: (context, _) => FutureBuilder(
        future: motor.imagen(productoId),
        initialData: motor.imagenEnMemoria(productoId)?.$1,
        builder: (context, foto) => marco(foto.data == null
            ? vacio
            : Image.memory(foto.data!, fit: BoxFit.contain, gaplessPlayback: true, errorBuilder: (_, _, _) => vacio)),
      ),
    );
  }
}

/// Pie de pantalla con los datos de propiedad de ODAI y la versión instalada.
class PieOdai extends StatelessWidget {
  const PieOdai({super.key});

  @override
  Widget build(BuildContext context) {
    final estilo = Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600);
    return SafeArea(
      top: false,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Divider(height: 1, thickness: 1, color: Colors.grey.shade300),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text('Derechos reservados © ODAI | www.odai.lat | Versión $appVersion',
              textAlign: TextAlign.center, style: estilo),
        ),
      ]),
    );
  }
}
