import 'package:flutter/material.dart';

import '../actualizar.dart';
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
          child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text('Derechos reservados © ODAI  |  ', style: estilo),
            InkWell(
              onTap: () => abrirEnNavegador('https://www.odai.lat'),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('www.odai.lat',
                    style: estilo?.copyWith(
                        color: Theme.of(context).colorScheme.primary, decoration: TextDecoration.underline)),
              ),
            ),
            Text('  |  Versión $appVersion', style: estilo),
          ]),
        ),
      ]),
    );
  }
}

/// Una acción de la barra: icono con su texto. La principal va rellena, las demás con marco.
class Accion {
  const Accion(this.icono, this.texto, this.onPressed, {this.principal = false});

  final IconData icono;
  final String texto;
  final VoidCallback? onPressed;
  final bool principal;
}

/// Barra de acciones debajo del título, igual en todas las pantallas: a la izquierda el menú "⋮ Acciones" con las
/// demás opciones y al lado la acción más importante de la pantalla. Así nunca se pasa del ancho del celular.
class BarraAcciones extends StatelessWidget {
  const BarraAcciones({super.key, required this.acciones});

  final List<Accion> acciones;

  @override
  Widget build(BuildContext context) {
    if (acciones.isEmpty) return const SizedBox.shrink();
    const alto = Size(0, 44);
    final principal = acciones.where((a) => a.principal).firstOrNull;
    final resto = acciones.where((a) => a != principal).toList();
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade400)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(children: [
        if (resto.isNotEmpty)
          MenuAnchor(
            menuChildren: [
              for (final a in resto)
                MenuItemButton(
                  key: ValueKey('accion_${a.texto}'),
                  leadingIcon: Icon(a.icono),
                  onPressed: a.onPressed,
                  child: Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(a.texto)),
                ),
            ],
            builder: (context, menu, _) => OutlinedButton.icon(
              key: const ValueKey('acciones'),
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
              style: OutlinedButton.styleFrom(minimumSize: alto),
              icon: const Icon(Icons.more_vert, size: 20),
              label: const Text('Acciones'),
            ),
          ),
        if (resto.isNotEmpty && principal != null) const SizedBox(width: 8),
        if (principal != null)
          Flexible(
            child: FilledButton.icon(
              key: ValueKey('accion_${principal.texto}'),
              onPressed: principal.onPressed,
              style: FilledButton.styleFrom(minimumSize: alto),
              icon: Icon(principal.icono, size: 20),
              label: Text(principal.texto, overflow: TextOverflow.ellipsis),
            ),
          ),
      ]),
    );
  }
}

/// Filtros como las facetas de Odoo: uno elegido, resaltado.
class Filtros<T> extends StatelessWidget {
  const Filtros({super.key, required this.opciones, required this.elegido, required this.onChanged});

  final List<(T, String)> opciones;
  final T elegido;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        for (final (i, o) in opciones.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          ChoiceChip(
            label: Text(o.$2),
            selected: o.$1 == elegido,
            showCheckmark: false,
            selectedColor: tema.colorScheme.secondary.withValues(alpha: 0.18),
            side: BorderSide(color: o.$1 == elegido ? tema.colorScheme.secondary : Colors.grey.shade500),
            labelStyle: TextStyle(
                color: const Color(0xFF111111), fontWeight: o.$1 == elegido ? FontWeight.w700 : FontWeight.w500),
            onSelected: (_) => onChanged(o.$1),
          ),
        ],
      ]),
    );
  }
}
