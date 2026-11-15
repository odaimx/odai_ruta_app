import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../actualizar.dart';
import '../api.dart';
import '../motor.dart';
import '../tema.dart';
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

/// Cabecera morada de todas las pantallas: el nombre grande en blanco y el logo de ODAI a la derecha.
class CabeceraOdai extends StatelessWidget implements PreferredSizeWidget {
  const CabeceraOdai({super.key, required this.titulo, this.subtitulo, this.derecha});

  final String titulo;
  final String? subtitulo;

  /// Lo que va a la derecha en lugar del logo (por ejemplo, la señal en la pantalla del PIN).
  final Widget? derecha;

  @override
  Size get preferredSize => Size.fromHeight(subtitulo == null ? 64 : 76);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: preferredSize.height,
      titleSpacing: Navigator.canPop(context) ? 0 : 16,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
        ),
        if (subtitulo != null && subtitulo!.isNotEmpty)
          Text(subtitulo!,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500)),
      ]),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 14),
          child: derecha ?? Image.asset('assets/logo_blanco.png', height: 26, fit: BoxFit.contain),
        ),
      ],
    );
  }
}

/// Señal con Odoo: barras verdes "Online" si hubo comunicación hace poco; rojas "Offline" si no.
class IndicadorSenal extends StatelessWidget {
  const IndicadorSenal({super.key, required this.motor, this.claro = false});

  final Motor motor;

  /// Letra blanca (sobre la cabecera morada).
  final bool claro;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: motor,
      builder: (context, _) {
        final enLinea = motor.conSenal;
        final color = enLinea ? verdeOdai : const Color(0xFFE53935);
        return Semantics(
          label: enLinea ? 'Con señal' : 'Sin señal',
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
            Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final alto in const [8.0, 13.0, 18.0, 24.0])
                Container(
                  width: 6,
                  height: alto,
                  margin: const EdgeInsets.only(left: 2.5),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
                ),
            ]),
            const SizedBox(height: 2),
            Text(enLinea ? 'Online' : 'Offline',
                style: TextStyle(fontSize: 11, color: claro ? Colors.white : const Color(0xFF222222))),
          ]),
        );
      },
    );
  }
}

/// Tarjeta con el marco morado de las maquetas.
class TarjetaOdai extends StatelessWidget {
  const TarjetaOdai({super.key, required this.child, this.onTap, this.padding = const EdgeInsets.all(12), this.margen});

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final EdgeInsets? margen;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: margen ?? const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

/// Barra con degradado (morado o azul) para las tarjetas del inicio.
class BarraAvance extends StatelessWidget {
  const BarraAvance({super.key, required this.valor, this.azul = false, this.alto = 20});

  /// De 0 a 1.
  final double valor;
  final bool azul;
  final double alto;

  @override
  Widget build(BuildContext context) {
    final color = azul ? azulOdai : moradoOdai;
    final v = valor.isNaN ? 0.0 : valor.clamp(0.0, 1.0);
    return Container(
      height: alto,
      decoration: BoxDecoration(
        color: lavanda,
        borderRadius: BorderRadius.circular(4),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: v,
            heightFactor: 1,
            child: ColoredBox(color: color),
          ),
        ),
      ),
    );
  }
}

/// Buscador con la lupa a la derecha y, al lado, el botón para escanear un código de barras.
class Buscador extends StatelessWidget {
  const Buscador({super.key, required this.onChanged, this.onEscanear, this.hint = 'Buscar', this.controller});

  final ValueChanged<String> onChanged;
  final VoidCallback? onEscanear;
  final String hint;
  final TextEditingController? controller;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Expanded(
        child: TextField(
          controller: controller,
          decoration: InputDecoration(
            hintText: hint,
            suffixIcon: const Icon(Icons.search, size: 28, color: Color(0xFF111111)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          ),
          onChanged: onChanged,
        ),
      ),
      if (onEscanear != null) ...[
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          height: 50,
          child: OutlinedButton(
            key: const ValueKey('escanear'),
            onPressed: onEscanear,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero, backgroundColor: Colors.white),
            child: const Icon(Icons.qr_code_scanner, size: 30, color: Color(0xFF111111)),
          ),
        ),
      ],
    ]);
  }
}

/// Lector de códigos de barras con la cámara: regresa el código leído.
class Escaner extends StatefulWidget {
  const Escaner({super.key, this.titulo = 'Escanear código'});

  final String titulo;

  @override
  State<Escaner> createState() => _EscanerState();
}

class _EscanerState extends State<Escaner> {
  final _camara = MobileScannerController();
  bool _listo = false;

  @override
  void dispose() {
    _camara.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.titulo)),
      body: MobileScanner(
        controller: _camara,
        onDetect: (captura) {
          final valor = captura.barcodes.firstOrNull?.rawValue;
          if (valor != null && !_listo) {
            _listo = true;
            Navigator.pop(context, valor);
          }
        },
      ),
    );
  }
}

Future<String?> escanear(BuildContext context, {String titulo = 'Escanear código'}) =>
    Navigator.push<String>(context, MaterialPageRoute(builder: (_) => Escaner(titulo: titulo)));

/// Pie de pantalla con los datos de propiedad de ODAI y la versión instalada.
class PieOdai extends StatelessWidget {
  const PieOdai({super.key});

  @override
  Widget build(BuildContext context) {
    const estilo = TextStyle(fontSize: 13, color: Color(0xFF222222));
    return Container(
      color: fondoOdai,
      child: SafeArea(
        top: false,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Divider(height: 2, thickness: 2, color: moradoCabecera),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
              const Text('Derechos reservados © ODAI | ', style: estilo),
              InkWell(
                onTap: () => abrirEnNavegador('https://www.odai.lat'),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text('www.odai.lat',
                      style: TextStyle(fontSize: 13, color: Color(0xFF1A3FD1), decoration: TextDecoration.underline)),
                ),
              ),
              const Text(' | V. $appVersion', style: estilo),
            ]),
          ),
        ]),
      ),
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

/// Barra de acciones debajo de la cabecera, igual en todas las pantallas: a la izquierda el menú ⋮ con las demás
/// opciones, al lado la acción más importante de la pantalla y a la derecha la señal. Así nunca se pasa del ancho
/// del celular. ``centro`` pone algo en medio (en el pedido: disponible y por cobrar del cliente).
class BarraAcciones extends StatelessWidget {
  const BarraAcciones({super.key, required this.acciones, this.motor, this.centro});

  final List<Accion> acciones;
  final Motor? motor;
  final Widget? centro;

  @override
  Widget build(BuildContext context) {
    const alto = Size(0, 46);
    final principal = acciones.where((a) => a.principal).firstOrNull;
    final resto = acciones.where((a) => a != principal).toList();
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: fondoOdai,
        border: Border(bottom: BorderSide(color: moradoCabecera, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
      child: Row(children: [
        if (resto.isNotEmpty)
          MenuAnchor(
            menuChildren: [
              for (final a in resto)
                MenuItemButton(
                  key: ValueKey('accion_${a.texto}'),
                  leadingIcon: Icon(a.icono, color: moradoOscuro),
                  onPressed: a.onPressed,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(a.texto, style: const TextStyle(fontSize: 16)),
                  ),
                ),
            ],
            builder: (context, menu, _) => IconButton(
              key: const ValueKey('acciones'),
              tooltip: 'Acciones',
              onPressed: () => menu.isOpen ? menu.close() : menu.open(),
              icon: const Icon(Icons.more_vert, size: 32, color: Color(0xFF111111)),
            ),
          )
        else
          const SizedBox(width: 8),
        if (principal != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: FilledButton.icon(
              key: ValueKey('accion_${principal.texto}'),
              onPressed: principal.onPressed,
              style: FilledButton.styleFrom(minimumSize: alto, backgroundColor: moradoOdai),
              icon: Icon(principal.icono, size: 22),
              label: Text(principal.texto, overflow: TextOverflow.ellipsis),
            ),
          ),
        Expanded(child: centro == null ? const SizedBox.shrink() : Align(alignment: Alignment.centerRight, child: centro)),
        if (motor != null) ...[const SizedBox(width: 10), IndicadorSenal(motor: motor!)],
      ]),
    );
  }
}

/// Filtros como cajas, igual de anchas: la elegida con relleno lavanda.
class Filtros<T> extends StatelessWidget {
  const Filtros({super.key, required this.opciones, required this.elegido, required this.onChanged});

  final List<(T, String)> opciones;
  final T elegido;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(children: [
        for (final (i, o) in opciones.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              onPressed: () => onChanged(o.$1),
              style: OutlinedButton.styleFrom(
                backgroundColor: o.$1 == elegido ? lavanda : Colors.white,
                minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 6),
              ),
              child: FittedBox(
                child: Text(o.$2,
                    style: TextStyle(
                        fontSize: 16,
                        color: const Color(0xFF111111),
                        fontWeight: o.$1 == elegido ? FontWeight.w700 : FontWeight.w500)),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}


/// Billetes con los que suele pagar el cliente: con 145 se sugiere 150, 200, 500 y 1,000.
List<double> montosSugeridos(double total) {
  if (total <= 0) return const [];
  final r = <double>{};
  for (final b in const [50, 100, 200, 500, 1000]) {
    final v = (total / b).ceil() * b.toDouble();
    if (v > total + 0.004) r.add(v);
  }
  return (r.toList()..sort()).take(4).toList();
}

/// Captura rápida de lo que entrega el cliente: Exacto, los billetes sugeridos y Manual (escribir la cantidad).
class MontosRapidos extends StatelessWidget {
  const MontosRapidos({super.key, required this.total, required this.moneda, required this.onElegir, this.onManual});

  final double total;
  final String Function(num) moneda;
  final ValueChanged<double> onElegir;
  final VoidCallback? onManual;

  @override
  Widget build(BuildContext context) {
    Widget boton(String texto, VoidCallback onTap, {Key? key}) => OutlinedButton(
          key: key,
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
              backgroundColor: lavanda, minimumSize: const Size(0, 44), padding: const EdgeInsets.symmetric(horizontal: 12)),
          child: Text(texto, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        );
    String redondo(num v) => moneda(v).replaceAll(RegExp(r'\.00$'), '');
    return Wrap(spacing: 8, runSpacing: 8, children: [
      boton('Exacto', () => onElegir(total), key: const ValueKey('monto_exacto')),
      for (final m in montosSugeridos(total)) boton(redondo(m), () => onElegir(m), key: ValueKey('monto_${m.toInt()}')),
      if (onManual != null) boton('Manual', onManual!, key: const ValueKey('monto_manual')),
    ]);
  }
}

/// Anillo de avance (estilo tablero BI): el porcentaje en medio.
class Anillo extends StatelessWidget {
  const Anillo({super.key, required this.valor, this.color = moradoOdai, this.lado = 84, this.centro});

  final double valor;
  final Color color;
  final double lado;
  final Widget? centro;

  @override
  Widget build(BuildContext context) {
    final v = valor.isNaN ? 0.0 : valor.clamp(0.0, 1.0);
    return SizedBox(
      width: lado,
      height: lado,
      child: CustomPaint(
        painter: _PintorAnillo(v, color),
        child: Center(
          child: centro ??
              Text('${(v * 100).round()}%',
                  style: TextStyle(fontSize: lado * 0.22, fontWeight: FontWeight.w800, color: const Color(0xFF111111))),
        ),
      ),
    );
  }
}

class _PintorAnillo extends CustomPainter {
  _PintorAnillo(this.valor, this.color);

  final double valor;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final grueso = size.width * 0.12;
    final rect = Offset.zero & size;
    final area = rect.deflate(grueso / 2);
    canvas.drawArc(area, 0, 2 * math.pi, false,
        Paint()..style = PaintingStyle.stroke..strokeWidth = grueso..color = lavanda);
    if (valor > 0) {
      canvas.drawArc(area, -math.pi / 2, 2 * math.pi * valor, false,
          Paint()..style = PaintingStyle.stroke..strokeWidth = grueso..strokeCap = StrokeCap.round..color = color);
    }
  }

  @override
  bool shouldRepaint(_PintorAnillo old) => old.valor != valor || old.color != color;
}
