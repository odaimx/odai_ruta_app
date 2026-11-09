import 'dart:math' as math;

import 'base_local.dart';
import 'motor.dart';

double _num(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0.0;

/// Formato de dinero con la moneda de la empresa.
class Moneda {
  const Moneda({this.simbolo = r'$', this.antes = true, this.decimales = 2});

  factory Moneda.desde(Object? json) {
    if (json is! Map) return const Moneda();
    return Moneda(
      simbolo: (json['symbol'] as String?) ?? r'$',
      antes: json['position'] != 'after',
      decimales: (json['decimals'] as int?) ?? 2,
    );
  }

  final String simbolo;
  final bool antes;
  final int decimales;

  String call(num valor) {
    final negativo = valor < 0;
    final partes = valor.abs().toStringAsFixed(decimales).split('.');
    final entero = partes.first.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
    final texto = partes.length > 1 ? '$entero.${partes[1]}' : entero;
    final conSimbolo = antes ? '$simbolo$texto' : '$texto $simbolo';
    return negativo ? '-$conSimbolo' : conSimbolo;
  }

  double redondear(num valor) {
    final f = math.pow(10, decimales);
    return (valor * f).round() / f;
  }
}

/// Un renglón del carrito.
class Linea {
  Linea({required this.producto, required this.cantidad, this.uomId});

  final Map producto;
  double cantidad;
  int? uomId;

  int get productId => producto['id'] as int;

  String get unidad {
    if (uomId == null) return (producto['uom'] as String?) ?? '';
    final uom = ((producto['uoms'] as List?) ?? const []).whereType<Map>().where((u) => u['id'] == uomId);
    return uom.isEmpty ? '' : (uom.first['name'] as String? ?? '');
  }

  Map<String, Object?> paraOdoo() => {
        'product_id': productId,
        'cantidad': cantidad,
        if (uomId != null) 'uom_id': uomId,
      };
}

/// Lo que el vendedor ve de su ruta, armado con lo que bajó de Odoo más lo que aún espera en la cola (así un
/// pedido capturado sin señal ya se ve en la lista y en el saldo del cliente).
class Ruta {
  Ruta._(this.jornadas, this.catalogo, this._listas, this._visitaLista, this._iva, this._facturas, this.motivos,
      this._pendientes);

  final List<Map> jornadas;
  final List<Map> catalogo;
  final Map _listas;
  final Map _visitaLista;
  final Map _iva;
  final Map _facturas;
  final List<Map> motivos;
  final List<Operacion> _pendientes;

  static Future<Ruta> cargar(Motor motor) async {
    List<Map> lista(Object? v) => ((v as List?) ?? const []).whereType<Map>().toList();
    Map mapa(Object? v) => (v as Map?) ?? const {};
    final pendientes = await motor.cola?.pendientes(limite: 100000) ?? const <Operacion>[];
    return Ruta._(
      lista(await motor.dato('jornadas')),
      lista(await motor.dato('catalogo')).where((p) => ((p['combo'] as List?) ?? const []).isEmpty).toList(),
      mapa(await motor.dato('listas')),
      mapa(await motor.dato('visita_lista')),
      mapa(await motor.dato('iva')),
      mapa(await motor.dato('facturas')),
      lista(await motor.dato('motivos')),
      pendientes,
    );
  }

  Map? jornada(int id) {
    for (final j in jornadas) {
      if ((j['jornada'] as Map?)?['id'] == id) return j;
    }
    return null;
  }

  Map config(int jornadaId) => (jornada(jornadaId)?['config'] as Map?) ?? const {};

  Moneda moneda(int jornadaId) => Moneda.desde(config(jornadaId)['moneda']);

  Iterable<Operacion> _pendientesDe(int visitaId) => _pendientes.where((o) => o.datos['visita_id'] == visitaId);

  /// Estado de la visita contando lo que espera en la cola.
  String estado(Map visita) {
    final id = visita['id'] as int;
    final ops = _pendientesDe(id).toList();
    if (ops.any((o) => o.tipo == 'pedido')) return 'pedido';
    if (ops.any((o) => o.tipo == 'sin_venta')) return 'sin_venta';
    return (visita['estado'] as String?) ?? 'pendiente';
  }

  bool enCola(Map visita) => _pendientesDe(visita['id'] as int).isNotEmpty;

  /// Visitas de la jornada: pendientes primero (en orden de visita), luego las visitadas.
  List<Map> visitas(int jornadaId) {
    final todas = ((jornada(jornadaId)?['visitas'] as List?) ?? const []).whereType<Map>().toList();
    int orden(Map v) => estado(v) == 'pendiente' ? 0 : 1;
    todas.sort((a, b) {
      final c = orden(a) - orden(b);
      return c != 0 ? c : ((a['secuencia'] as int? ?? 0) - (b['secuencia'] as int? ?? 0));
    });
    return todas;
  }

  Map? visita(int jornadaId, int visitaId) {
    for (final v in visitas(jornadaId)) {
      if (v['id'] == visitaId) return v;
    }
    return null;
  }

  /// Facturas abiertas del cliente, descontando los cobros que esperan en la cola (de la más antigua a la más
  /// nueva, como los aplica Odoo).
  List<Map<String, Object?>> facturas(int visitaId) {
    final lista = ((_facturas['$visitaId'] as List?) ?? const [])
        .whereType<Map>()
        .map((f) => Map<String, Object?>.from(f))
        .toList();
    for (final cobro in _pendientesDe(visitaId).where((o) => o.tipo == 'cobro')) {
      var monto = _num(cobro.datos['monto']);
      final elegidas = ((cobro.datos['factura_ids'] as List?) ?? const []).toSet();
      for (final f in lista) {
        if (monto <= 0) break;
        if (elegidas.isNotEmpty && !elegidas.contains(f['id'])) continue;
        final aplicado = math.min(monto, _num(f['saldo']));
        f['saldo'] = _num(f['saldo']) - aplicado;
        monto -= aplicado;
      }
    }
    return lista.where((f) => _num(f['saldo']) > 0.004).toList();
  }

  double porCobrar(int visitaId) => facturas(visitaId).fold(0.0, (s, f) => s + _num(f['saldo']));

  /// Lo pedido sin señal que todavía no llega a Odoo (cuenta contra el crédito disponible).
  double pedidoEnCola(int visitaId) =>
      _pendientesDe(visitaId).where((o) => o.tipo == 'pedido').fold(0.0, (s, o) => s + _num(o.datos['total']));

  /// Precio sin impuestos para el cliente de la visita, con su lista de precios (si la tiene).
  double precio(int visitaId, Map producto, {int? uomId}) {
    final id = producto['id'];
    final tabla = _listas['${_visitaLista['$visitaId'] ?? '0'}'];
    final clave = uomId == null ? '$id' : '$id:$uomId';
    if (tabla is Map && tabla[clave] != null) return _num(tabla[clave]);
    if (uomId != null) {
      for (final u in ((producto['uoms'] as List?) ?? const []).whereType<Map>()) {
        if (u['id'] == uomId) return _num(u['precio']);
      }
    }
    return _num(producto['precio']);
  }

  /// Factor de impuestos (1.16 con IVA 16 %).
  double factorIva(int productId) {
    final f = _iva['$productId'];
    return f == null ? 1.0 : _num(f);
  }

  double subtotal(int visitaId, List<Linea> lineas) =>
      lineas.fold(0.0, (s, l) => s + precio(visitaId, l.producto, uomId: l.uomId) * l.cantidad);

  double total(int visitaId, List<Linea> lineas) => lineas.fold(
      0.0, (s, l) => s + precio(visitaId, l.producto, uomId: l.uomId) * l.cantidad * factorIva(l.productId));

  /// Busca por nombre, clave o código de barras. Un código de barras exacto devuelve también su embalaje.
  List<Map> buscar(String texto) {
    final t = texto.trim().toLowerCase();
    if (t.isEmpty) return catalogo.take(60).toList();
    return catalogo
        .where((p) =>
            '${p['name']}'.toLowerCase().contains(t) ||
            '${p['code']}'.toLowerCase().contains(t) ||
            ((p['barcodes'] as Map?) ?? const {}).containsKey(texto.trim()))
        .take(60)
        .toList();
  }

  /// Producto y embalaje de un código escaneado.
  (Map, int?)? porCodigo(String codigo) {
    for (final p in catalogo) {
      final codigos = (p['barcodes'] as Map?) ?? const {};
      if (codigos.containsKey(codigo)) {
        final uom = codigos[codigo];
        return (p, uom == p['uom_id'] ? null : uom as int?);
      }
    }
    return null;
  }
}
