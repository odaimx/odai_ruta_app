import 'package:flutter/material.dart';

import '../motor.dart';
import '../ruta.dart';
import '../tema.dart';
import 'cliente.dart';
import 'cliente_datos.dart';
import 'cobro.dart';
import 'comun.dart';
import 'sin_venta.dart';

/// Levantar pedido: buscar o escanear productos, carrito, contado o crédito, factura. El precio lo pone la lista
/// de precios del cliente; el vendedor no lo cambia (si está mal, la oficina corrige la lista).
class PantallaPedido extends StatefulWidget {
  const PantallaPedido({super.key, required this.motor, required this.jornadaId, required this.visitaId});

  final Motor motor;
  final int jornadaId;
  final int visitaId;

  @override
  State<PantallaPedido> createState() => _PantallaPedidoState();
}

class _PantallaPedidoState extends State<PantallaPedido> {
  Ruta? _ruta;
  Map? _visita;
  final _lineas = <Linea>[];
  final _uomElegido = <int, int>{};
  String _busqueda = '';
  bool _contado = false;
  bool _factura = false;
  final _nota = TextEditingController();
  bool _enviando = false;

  @override
  void initState() {
    super.initState();
    Ruta.cargar(widget.motor).then((r) {
      final v = r.visita(widget.jornadaId, widget.visitaId);
      if (!mounted) return;
      setState(() {
        _ruta = r;
        _visita = v;
        _contado = ((v?['credito'] as Map?)?['a_credito']) != true;
        // Pide factura por costumbre, pero solo se marca sola si ya tiene sus datos fiscales.
        _factura = v?['pide_factura'] == true && v != null && r.faltanFiscales(widget.jornadaId, v).isEmpty;
      });
    });
  }

  /// Vuelve a leer la visita (después de cobrar o de modificar el cliente) sin perder el carrito.
  Future<void> _recargar() async {
    final r = await Ruta.cargar(widget.motor);
    if (!mounted) return;
    setState(() {
      _ruta = r;
      _visita = r.visita(widget.jornadaId, widget.visitaId) ?? _visita;
    });
  }

  Future<void> _ir(Widget pantalla) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => pantalla));
    await _recargar();
  }

  Future<void> _sinVenta() async {
    if (_lineas.isNotEmpty &&
        !await confirmar(context, 'Sin venta', 'Ya agregó productos. ¿Descartarlos y registrar la visita sin venta?',
            si: 'Sin venta')) {
      return;
    }
    if (!mounted) return;
    await _ir(PantallaSinVenta(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId));
    if (mounted && _ruta != null && _visita != null && _ruta!.estado(_visita!) == 'sin_venta') Navigator.pop(context);
  }

  Future<void> _modificarCliente() => _ir(
      PantallaDatosCliente(motor: widget.motor, jornadaId: widget.jornadaId, visita: _visita));

  /// Para pedir factura el cliente necesita sus datos fiscales: si faltan, se ofrece completarlos ahí mismo.
  Future<bool> _puedeFacturar() async {
    final faltan = _ruta!.faltanFiscales(widget.jornadaId, _visita!);
    if (faltan.isEmpty) return true;
    final completar = await confirmar(
        context,
        'Faltan datos fiscales',
        'Para facturarle a su nombre falta: ${faltan.join(', ')}. Complételos en Modificar cliente con la '
            'Constancia de Situación Fiscal.',
        si: 'Completar');
    if (!completar || !mounted) return false;
    await _modificarCliente();
    if (!mounted) return false;
    final siguen = _ruta!.faltanFiscales(widget.jornadaId, _visita!);
    if (siguen.isNotEmpty) avisar(context, 'Aún falta: ${siguen.join(', ')}.', error: true);
    return siguen.isEmpty;
  }

  @override
  void dispose() {
    _nota.dispose();
    super.dispose();
  }

  void _agregar(Map producto, {int? uomId, double cantidad = 1}) {
    setState(() {
      final existente = _lineas.where((l) => l.productId == producto['id'] && l.uomId == uomId);
      if (existente.isNotEmpty) {
        existente.first.cantidad += cantidad;
      } else {
        _lineas.add(Linea(producto: producto, cantidad: cantidad, uomId: uomId));
      }
    });
  }

  Future<void> _escanear() async {
    final codigo = await escanear(context, titulo: 'Escanear producto');
    if (codigo == null || !mounted) return;
    final hallado = _ruta!.porCodigo(codigo);
    if (hallado == null) {
      avisar(context, 'No hay un producto con el código $codigo.', error: true);
      return;
    }
    _agregar(hallado.$1, uomId: hallado.$2);
    avisar(context, 'Agregado: ${hallado.$1['name']}');
  }

  Future<void> _enviar() async {
    if (_factura && !await _puedeFacturar()) {
      if (mounted) avisar(context, 'Sin datos fiscales completos no se puede enviar con factura.', error: true);
      return;
    }
    if (!mounted) return;
    final ruta = _ruta!;
    final v = _visita!;
    final moneda = ruta.moneda(widget.jornadaId);
    final total = moneda.redondear(ruta.total(widget.visitaId, _lineas));
    final credito = (v['credito'] as Map?) ?? const {};
    final disponible = credito['disponible_ruta'];
    if (!_contado && disponible is num && total > disponible - ruta.pedidoEnCola(widget.visitaId)) {
      final seguir = await confirmar(context, 'Crédito insuficiente',
          'El pedido (${moneda(total)}) pasa del crédito disponible. Odoo lo dejará retenido para que la oficina '
              'decida. ¿Enviarlo así? También puede cambiarlo a contado.',
          si: 'Enviar');
      if (!seguir || !mounted) return;
    }
    setState(() => _enviando = true);
    try {
      final uuid = await widget.motor.registrar('pedido', {
        'visita_id': widget.visitaId,
        'lineas': _lineas.map((l) => l.paraOdoo()).toList(),
        'nota': _nota.text.trim(),
        'contado': _contado,
        'factura': _factura,
        'subtotal': moneda.redondear(ruta.subtotal(widget.visitaId, _lineas)),
        'total': total,
        'sin_senal': !widget.motor.conSenal,
      });
      if (!mounted) return;
      final config = ruta.config(widget.jornadaId);
      if (_contado && config['cobro_venta'] != null && config['cobro_venta'] != 'no') {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => _CobroAlVender(
            motor: widget.motor,
            visitaId: widget.visitaId,
            pedidoUuid: uuid,
            total: total,
            moneda: moneda,
            config: config,
          ),
        );
      }
      if (mounted) {
        avisar(context, 'Pedido por ${moneda(total)} guardado.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _enviando = false);
        avisar(context, textoError(e), error: true);
      }
    }
  }

  Linea? _linea(Map producto, int? uomId) {
    for (final l in _lineas) {
      if (l.productId == producto['id'] && l.uomId == uomId) return l;
    }
    return null;
  }

  double _cantidad(Map producto, int? uomId) => _linea(producto, uomId)?.cantidad ?? 0;

  void _poner(Map producto, int? uomId, double cantidad) {
    setState(() {
      final l = _linea(producto, uomId);
      if (cantidad <= 0) {
        if (l != null) _lineas.remove(l);
      } else if (l != null) {
        l.cantidad = cantidad;
      } else {
        _lineas.add(Linea(producto: producto, cantidad: cantidad, uomId: uomId));
      }
    });
  }

  /// Teclear la cantidad (también decimales, para productos a granel).
  Future<void> _teclear(Map producto, int? uomId) async {
    final actual = _cantidad(producto, uomId);
    final control = TextEditingController(text: actual > 0 ? _textoCantidad(actual) : '');
    final r = await showDialog<double>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('${producto['name']}'),
        content: TextField(
          controller: control,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Cantidad'),
          onSubmitted: (t) => Navigator.pop(c, double.tryParse(t.replaceAll(',', '.')) ?? 0),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.pop(c, double.tryParse(control.text.replaceAll(',', '.')) ?? 0),
            child: const Text('Listo'),
          ),
        ],
      ),
    );
    if (r != null) _poner(producto, uomId, r);
  }

  static String _textoCantidad(double c) => c == c.roundToDouble() ? '${c.toInt()}' : '$c';

  Widget _fila(Ruta ruta, Moneda moneda, Map p) {
    final uoms = ((p['uoms'] as List?) ?? const []).whereType<Map>().toList();
    final uomId = _uomElegido[p['id']];
    final unidad = uomId == null ? '${p['uom']}' : '${uoms.firstWhere((u) => u['id'] == uomId)['name']}';
    final cantidad = _cantidad(p, uomId);
    final kit = ((p['kit'] as List?) ?? const []).whereType<Map>().toList();
    final enCarrito = _lineas.where((l) => l.productId == p['id']).fold(0.0, (s, l) => s + l.cantidad);
    final mostrarFoto = ruta.config(widget.jornadaId)['imagenes'] == true ||
        (p['imagen'] is String && (p['imagen'] as String).isNotEmpty);
    Widget unidadChip(String nombre, bool elegida, VoidCallback onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: Container(
            constraints: const BoxConstraints(minWidth: 96, minHeight: 36),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: lavanda,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: elegida ? moradoOdai : bordeMorado, width: elegida ? 1.6 : 1),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (elegida) const Padding(padding: EdgeInsets.only(right: 4), child: Icon(Icons.check, size: 18)),
              Text(nombre,
                  style: TextStyle(fontSize: 14, fontWeight: elegida ? FontWeight.w700 : FontWeight.w500,
                      color: const Color(0xFF111111))),
            ]),
          ),
        );
    return TarjetaOdai(
      key: ValueKey('producto_${p['id']}'),
      margen: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      child: Row(children: [
        if (mostrarFoto)
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Miniatura(motor: widget.motor, productoId: p['id'] as int, lado: 50),
          ),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${p['name']}'.toUpperCase(),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF222222))),
            Text('${moneda(ruta.precio(widget.visitaId, p, uomId: uomId))} / $unidad',
                style: const TextStyle(fontSize: 16, color: Color(0xFF222222))),
            if (kit.isNotEmpty)
              Text('Kit: ${kit.map((k) => '${k['cantidad']} ${k['name']}').join(', ')}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF333333))),
            if (uoms.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  unidadChip('${p['uom']}', uomId == null, () => setState(() => _uomElegido.remove(p['id']))),
                  for (final u in uoms)
                    unidadChip('${u['name']}', uomId == u['id'],
                        () => setState(() => _uomElegido[p['id'] as int] = u['id'] as int)),
                ]),
              ),
            if (enCarrito > 0 && cantidad == 0)
              Text('En el pedido: ${_textoCantidad(enCarrito)} en otra unidad',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: moradoOscuro)),
          ]),
        ),
        if (cantidad == 0)
          SizedBox(
            width: 50,
            height: 46,
            child: OutlinedButton(
              key: ValueKey('agregar_${p['id']}'),
              onPressed: () => _poner(p, uomId, 1),
              style: OutlinedButton.styleFrom(backgroundColor: lavanda, padding: EdgeInsets.zero),
              child: const Icon(Icons.add, size: 36, color: Color(0xFF111111)),
            ),
          )
        else
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: moradoOscuro),
              iconSize: 30,
              onPressed: () => _poner(p, uomId, cantidad - 1),
            ),
            InkWell(
              onTap: () => _teclear(p, uomId),
              child: Container(
                constraints: const BoxConstraints(minWidth: 44),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: lavanda,
                  border: Border.all(color: moradoOdai),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_textoCantidad(cantidad),
                    textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add_circle_outline, color: moradoOscuro),
              iconSize: 30,
              onPressed: () => _poner(p, uomId, cantidad + 1),
            ),
          ]),
      ]),
    );
  }

  /// Revisar antes de enviar: renglones, contado o crédito, factura y nota.
  Future<void> _revisar() async {
    final ruta = _ruta!;
    final v = _visita!;
    final moneda = ruta.moneda(widget.jornadaId);
    final aCredito = ((v['credito'] as Map?)?['a_credito']) == true;
    final enviar = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, refrescar) {
          void cambiar(VoidCallback f) {
            setState(f);
            refrescar(() {});
          }

          final total = ruta.total(widget.visitaId, _lineas);
          return Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(c).viewInsets.bottom),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.of(c).size.height * 0.85),
              child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(16, 0, 16, 16), children: [
                Text('Pedido de ${v['cliente']}', style: Theme.of(c).textTheme.titleLarge),
                for (final l in List.of(_lineas))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${l.producto['name']}'),
                    subtitle: Text('${_textoCantidad(l.cantidad)} ${l.unidad} × '
                        '${moneda(ruta.precio(widget.visitaId, l.producto, uomId: l.uomId))}'),
                    trailing: IconButton(
                      tooltip: 'Quitar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => cambiar(() => _lineas.remove(l)),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('De contado'),
                  subtitle: Text([
                    if (!aCredito) 'Este cliente no tiene crédito',
                    if (_contado && ruta.config(widget.jornadaId)['tipo_ruta'] == 'preventa') 'Preventa: lo cobra el chofer al entregar',
                  ].join('. ')),
                  value: _contado,
                  onChanged: aCredito ? (x) => cambiar(() => _contado = x) : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Quiere factura'),
                  value: _factura,
                  subtitle: ruta.faltanFiscales(widget.jornadaId, _visita!).isEmpty
                      ? null
                      : Text('Faltan: ${ruta.faltanFiscales(widget.jornadaId, _visita!).join(', ')}',
                          style: TextStyle(color: Theme.of(c).colorScheme.error)),
                  onChanged: (x) async {
                    if (x && !await _puedeFacturar()) return;
                    cambiar(() => _factura = x);
                  },
                ),
                TextField(controller: _nota, decoration: const InputDecoration(labelText: 'Nota'), maxLines: 2),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const ValueKey('enviar_pedido'),
                  onPressed: _lineas.isEmpty ? null : () => Navigator.pop(c, true),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(62)),
                  icon: const Icon(Icons.send, size: 28),
                  label: Text('Enviar ${moneda(total)}',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                ),
              ]),
            ),
          );
        },
      ),
    );
    if (enviar == true) await _enviar();
  }

  @override
  Widget build(BuildContext context) {
    final ruta = _ruta;
    final v = _visita;
    if (ruta == null || v == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final moneda = ruta.moneda(widget.jornadaId);
    final resultados = ruta.buscar(_busqueda);
    final total = ruta.total(widget.visitaId, _lineas);
    final piezas = _lineas.length;
    final credito = (v['credito'] as Map?) ?? const {};
    final disponible = credito['disponible_ruta'];
    final textoDisponible = credito['a_credito'] == true
        ? (disponible is num ? moneda(disponible - ruta.pedidoEnCola(widget.visitaId)) : 'Sin límite')
        : 'Contado';
    final abierta = (ruta.jornada(widget.jornadaId)?['jornada'] as Map?)?['state'] == 'abierta';
    const chico = TextStyle(fontSize: 15, color: Color(0xFF111111));
    return Scaffold(
      appBar: CabeceraOdai(
          titulo: widget.motor.nombreVendedor.isEmpty ? '${v['cliente']}' : widget.motor.nombreVendedor,
          subtitulo: '${(v['comercial'] as String?)?.isNotEmpty == true ? v['comercial'] : v['cliente']}'),
      body: Column(children: [
        BarraAcciones(
          motor: widget.motor,
          acciones: [
            Accion(Icons.person, 'Ver ficha del cliente',
                () => _ir(PantallaCliente(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId))),
            if (abierta && ruta.cobra(widget.jornadaId))
              Accion(Icons.payments, 'Cobrar',
                  () => _ir(PantallaCobro(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: widget.visitaId))),
            if (abierta && ruta.estado(v) == 'pendiente') Accion(Icons.block, 'Sin venta', _sinVenta),
            Accion(Icons.edit, 'Modificar cliente', _modificarCliente),
          ],
          centro: Table(
            key: const ValueKey('saldos'),
            defaultColumnWidth: const IntrinsicColumnWidth(),
            children: [
              TableRow(children: [
                const Text('Disponible:  ', style: chico),
                Text(textoDisponible, style: chico, textAlign: TextAlign.right),
              ]),
              TableRow(children: [
                const Text('Por cobrar:  ', style: chico),
                Text(moneda(ruta.porCobrar(widget.visitaId)), style: chico, textAlign: TextAlign.right),
              ]),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
          child: Buscador(
            hint: 'Nombre, clave o código',
            onChanged: (t) => setState(() => _busqueda = t),
            onEscanear: _escanear,
          ),
        ),
        Expanded(
          child: resultados.isEmpty
              ? const Center(child: Text('No hay productos con esa búsqueda.'))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: resultados.length,
                  itemBuilder: (_, i) => _fila(ruta, moneda, resultados[i]),
                ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: BotonGrande(
            icono: Icons.shopping_cart_checkout,
            texto: piezas == 0
                ? 'Agregue productos'
                : '${piezas == 1 ? '1 producto' : '$piezas productos'} · ${moneda(total)} · Revisar',
            onPressed: piezas == 0 || _enviando || !abierta ? null : _revisar,
          ),
        ),
      ),
    );
  }
}

/// Después de un pedido de contado: lo que entrega el cliente, su cambio y, si está activado, el cobro como
/// anticipo del pedido.
class _CobroAlVender extends StatefulWidget {
  const _CobroAlVender({
    required this.motor,
    required this.visitaId,
    required this.pedidoUuid,
    required this.total,
    required this.moneda,
    required this.config,
  });

  final Motor motor;
  final int visitaId;
  final String pedidoUuid;
  final double total;
  final Moneda moneda;
  final Map config;

  @override
  State<_CobroAlVender> createState() => _CobroAlVenderState();
}

class _CobroAlVenderState extends State<_CobroAlVender> {
  final _recibido = TextEditingController();
  final _referencia = TextEditingController();
  final _manual = FocusNode();
  int? _diario;

  List<Map> get _diarios => ((widget.config['diarios'] as List?) ?? const []).whereType<Map>().toList();
  bool get _registra => widget.config['cobro_venta'] == 'anticipo';
  Map? get _diarioElegido => _diarios.where((d) => d['id'] == _diario).firstOrNull;
  bool get _esTransferencia => _diarioElegido?['efectivo'] == false;

  @override
  void initState() {
    super.initState();
    final efectivo = _diarios.where((d) => d['efectivo'] == true);
    _diario = efectivo.isNotEmpty ? efectivo.first['id'] as int : _diarios.firstOrNull?['id'] as int?;
  }

  @override
  void dispose() {
    _recibido.dispose();
    _referencia.dispose();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _registrar() async {
    final recibido = double.tryParse(_recibido.text.replaceAll(',', '')) ?? 0;
    final monto = widget.moneda.redondear(_esTransferencia ? widget.total : (recibido < widget.total ? recibido : widget.total));
    if (_diario == null) {
      avisar(context, 'No hay formas de cobro configuradas. En Odoo: Ajustes › Venta en ruta › Formas de cobro.', error: true);
      return;
    }
    if (monto <= 0) {
      avisar(context, 'Escriba cuánto recibió.', error: true);
      return;
    }
    if (_esTransferencia && widget.config['a_bordo'] == true && _referencia.text.trim().isEmpty) {
      avisar(context, 'Escriba la referencia de la transferencia.', error: true);
      return;
    }
    try {
      await widget.motor.registrar('anticipo', {
        'visita_id': widget.visitaId,
        'pedido_uuid': widget.pedidoUuid,
        'journal_id': _diario,
        'monto': monto,
        'referencia': _referencia.text.trim(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) avisar(context, textoError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recibido = double.tryParse(_recibido.text.replaceAll(',', '')) ?? 0;
    final cambio = recibido - widget.total;
    return AlertDialog(
      title: Text('Total ${widget.moneda(widget.total)}'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (_registra && _diarios.length > 1) ...[
            const SizedBox(height: 8),
            DropdownButtonFormField<int>(
              initialValue: _diario,
              decoration: const InputDecoration(labelText: 'Forma de pago'),
              items: [for (final d in _diarios) DropdownMenuItem(value: d['id'] as int, child: Text('${d['name']}'))],
              onChanged: (x) => setState(() => _diario = x),
            ),
            const SizedBox(height: 16),
          ],
          if (_registra && _diarios.isEmpty)
            const Text('No hay formas de cobro configuradas en Odoo (Ajustes › Venta en ruta).',
                style: TextStyle(color: Colors.red)),
          if (!_esTransferencia) ...[
            const Align(alignment: Alignment.centerLeft, child: Text('¿Con cuánto paga?')),
            const SizedBox(height: 8),
            MontosRapidos(
              total: widget.total,
              moneda: widget.moneda.call,
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
              decoration: const InputDecoration(labelText: 'Recibido'),
              onChanged: (_) => setState(() {}),
            ),
          ],
          if (!_esTransferencia && recibido > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(cambio >= 0 ? 'Cambio ${widget.moneda(cambio)}' : 'Faltan ${widget.moneda(-cambio)}'),
            ),
          if (_registra && _esTransferencia) ...[
            const SizedBox(height: 16),
            TextField(controller: _referencia, decoration: const InputDecoration(labelText: 'Referencia de la transferencia')),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(_registra ? 'Después' : 'Listo')),
        if (_registra) FilledButton(onPressed: _registrar, child: const Text('Registrar cobro')),
      ],
    );
  }
}
