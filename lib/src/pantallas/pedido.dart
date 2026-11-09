import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../motor.dart';
import '../ruta.dart';
import 'comun.dart';

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
        _factura = v?['pide_factura'] == true;
      });
    });
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
    final codigo = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const _Escaner()));
    if (codigo == null || !mounted) return;
    final hallado = _ruta!.porCodigo(codigo);
    if (hallado == null) {
      avisar(context, 'No hay un producto con el código $codigo.', error: true);
      return;
    }
    _agregar(hallado.$1, uomId: hallado.$2);
    avisar(context, 'Agregado: ${hallado.$1['name']}');
  }

  Future<void> _elegir(Map producto) async {
    final uoms = ((producto['uoms'] as List?) ?? const []).whereType<Map>().toList();
    if (uoms.isEmpty) {
      _agregar(producto);
      return;
    }
    final ruta = _ruta!;
    final moneda = ruta.moneda(widget.jornadaId);
    final elegido = await showModalBottomSheet<int>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text('${producto['uom']}'),
            trailing: Text(moneda(ruta.precio(widget.visitaId, producto))),
            onTap: () => Navigator.pop(c, 0),
          ),
          for (final u in uoms)
            ListTile(
              title: Text('${u['name']}'),
              trailing: Text(moneda(ruta.precio(widget.visitaId, producto, uomId: u['id'] as int))),
              onTap: () => Navigator.pop(c, u['id'] as int),
            ),
        ]),
      ),
    );
    if (elegido != null) _agregar(producto, uomId: elegido == 0 ? null : elegido);
  }

  Future<void> _enviar() async {
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

  @override
  Widget build(BuildContext context) {
    final ruta = _ruta;
    final v = _visita;
    if (ruta == null || v == null) {
      return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
    }
    final moneda = ruta.moneda(widget.jornadaId);
    final aCredito = ((v['credito'] as Map?)?['a_credito']) == true;
    final resultados = ruta.buscar(_busqueda);
    final total = ruta.total(widget.visitaId, _lineas);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${v['cliente']}'),
          bottom: TabBar(tabs: [
            const Tab(text: 'Productos'),
            Tab(text: 'Pedido (${_lineas.length})'),
          ]),
          actions: [IconButton(tooltip: 'Escanear', onPressed: _escanear, icon: const Icon(Icons.qr_code_scanner))],
        ),
        body: TabBarView(children: [
          Column(children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: TextField(
                decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search), hintText: 'Nombre, clave o código', border: OutlineInputBorder()),
                onChanged: (t) => setState(() => _busqueda = t),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: resultados.length,
                itemBuilder: (_, i) {
                  final p = resultados[i];
                  final kit = ((p['kit'] as List?) ?? const []).whereType<Map>().toList();
                  return ListTile(
                    title: Text('${p['name']}'),
                    subtitle: kit.isEmpty
                        ? Text('${p['uom']}')
                        : Text('Kit: ${kit.map((k) => '${k['cantidad']} ${k['name']}').join(', ')}'),
                    trailing: Text(moneda(ruta.precio(widget.visitaId, p))),
                    onTap: () => _elegir(p),
                  );
                },
              ),
            ),
          ]),
          ListView(padding: const EdgeInsets.all(12), children: [
            if (_lineas.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Agregue productos.')),
            for (final l in _lineas)
              Card(
                child: ListTile(
                  title: Text('${l.producto['name']}'),
                  subtitle: Text('${l.unidad} · ${moneda(ruta.precio(widget.visitaId, l.producto, uomId: l.uomId))}'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(() {
                        l.cantidad -= 1;
                        if (l.cantidad <= 0) _lineas.remove(l);
                      }),
                    ),
                    Text(l.cantidad == l.cantidad.roundToDouble() ? '${l.cantidad.toInt()}' : '${l.cantidad}'),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: () => setState(() => l.cantidad += 1),
                    ),
                  ]),
                ),
              ),
            SwitchListTile(
              title: const Text('De contado'),
              subtitle: aCredito ? null : const Text('Este cliente no tiene crédito'),
              value: _contado,
              onChanged: aCredito ? (x) => setState(() => _contado = x) : null,
            ),
            SwitchListTile(
              title: const Text('Quiere factura'),
              value: _factura,
              onChanged: (x) => setState(() => _factura = x),
            ),
            TextField(controller: _nota, decoration: const InputDecoration(labelText: 'Nota'), maxLines: 2),
          ]),
        ]),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: BotonGrande(
              icono: Icons.send,
              texto: 'Enviar ${moneda(total)}',
              onPressed: _lineas.isEmpty || _enviando ? null : _enviar,
            ),
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
    super.dispose();
  }

  Future<void> _registrar() async {
    final recibido = double.tryParse(_recibido.text.replaceAll(',', '')) ?? 0;
    final monto = widget.moneda.redondear(_esTransferencia ? widget.total : (recibido < widget.total ? recibido : widget.total));
    if (monto <= 0 || _diario == null) return;
    if (_esTransferencia && widget.config['a_bordo'] == true && _referencia.text.trim().isEmpty) return;
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
          if (_registra && _diarios.length > 1)
            DropdownButtonFormField<int>(
              initialValue: _diario,
              decoration: const InputDecoration(labelText: 'Forma de pago'),
              items: [for (final d in _diarios) DropdownMenuItem(value: d['id'] as int, child: Text('${d['name']}'))],
              onChanged: (x) => setState(() => _diario = x),
            ),
          if (!_esTransferencia)
            TextField(
              controller: _recibido,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Recibido'),
              onChanged: (_) => setState(() {}),
            ),
          if (!_esTransferencia && recibido > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(cambio >= 0 ? 'Cambio ${widget.moneda(cambio)}' : 'Faltan ${widget.moneda(-cambio)}'),
            ),
          if (_registra && _esTransferencia)
            TextField(controller: _referencia, decoration: const InputDecoration(labelText: 'Referencia de la transferencia')),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(_registra ? 'Después' : 'Listo')),
        if (_registra) FilledButton(onPressed: _registrar, child: const Text('Registrar cobro')),
      ],
    );
  }
}

class _Escaner extends StatefulWidget {
  const _Escaner();

  @override
  State<_Escaner> createState() => _EscanerState();
}

class _EscanerState extends State<_Escaner> {
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
      appBar: AppBar(title: const Text('Escanear producto')),
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
