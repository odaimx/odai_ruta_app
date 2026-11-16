import 'dart:math' as math;

import 'base_local.dart';
import 'motor.dart';

/// RFC de público en general y de extranjeros: no sirven para facturar a nombre del cliente.
const rfcGenericos = {'XAXX010101000', 'XEXX010101000'};

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

/// Resumen del día del vendedor.
class Tablero {
  const Tablero({
    required this.vendido,
    required this.cobrado,
    required this.visitas,
    required this.hechas,
    required this.conPedido,
    required this.sinVenta,
  });

  final double vendido;
  final double cobrado;
  final int visitas;
  final int hechas;
  final int conPedido;
  final int sinVenta;

  int get pendientes => visitas - hechas;
}

/// Lo que el vendedor ve de su ruta, armado con lo que bajó de Odoo más lo que aún espera en la cola (así un
/// pedido capturado sin señal ya se ve en la lista y en el saldo del cliente).
class Ruta {
  Ruta._(
    this.jornadas,
    this.catalogo,
    this._listas,
    this._visitaLista,
    this._iva,
    this._facturas,
    this.motivos,
    this._pendientes,
    this._altasHechas,
  );

  final List<Map> jornadas;
  final List<Map> catalogo;
  final Map _listas;
  final Map _visitaLista;
  final Map _iva;
  final Map _facturas;
  final List<Map> motivos;
  final List<Operacion> _pendientes;

  /// Id provisional de un cliente nuevo que Odoo ya creó → lo que respondió (`visita_id` y `visita`).
  final Map<int, Map> _altasHechas;

  static Future<Ruta> cargar(Motor motor) async {
    List<Map> lista(Object? v) => ((v as List?) ?? const []).whereType<Map>().toList();
    Map mapa(Object? v) => (v as Map?) ?? const {};
    final pendientes = await motor.cola?.pendientes(limite: 100000) ?? const <Operacion>[];
    final hechas = await motor.cola?.altasHechas() ?? const <Operacion>[];
    return Ruta._(
      lista(await motor.dato('jornadas')),
      lista(await motor.dato('catalogo')).where((p) => ((p['combo'] as List?) ?? const []).isEmpty).toList(),
      mapa(await motor.dato('listas')),
      mapa(await motor.dato('visita_lista')),
      mapa(await motor.dato('iva')),
      mapa(await motor.dato('facturas')),
      lista(await motor.dato('motivos')),
      pendientes,
      {
        for (final a in hechas)
          if (a.resultado?['visita_id'] is int) idProvisional(a.uuid): {...a.resultado!, 'jornada_id': a.datos['jornada_id']},
      },
    );
  }

  Map? jornada(int id) {
    for (final j in jornadas) {
      if ((j['jornada'] as Map?)?['id'] == id) return j;
    }
    return null;
  }

  Map config(int jornadaId) => (jornada(jornadaId)?['config'] as Map?) ?? const {};

  /// Puede cobrar en la jornada (en reparto, si la ruta tiene "El chofer cobra") y hay formas de cobro.
  bool cobra(int jornadaId) =>
      config(jornadaId)['cobra'] != false && ((config(jornadaId)['diarios'] as List?) ?? const []).isNotEmpty;

  /// Mapa de la jornada: fondo (teselas), tolerancia, recorrido y aviso de ubicación.
  Map mapa(int jornadaId) => (config(jornadaId)['mapa'] as Map?) ?? const {};

  /// Odoo tiene el seguimiento GPS para la jornada (llegada y salida, fijar ubicación, recorrido y aviso).
  bool seguimiento(int jornadaId) => mapa(jornadaId)['seguimiento'] == true;

  /// La jornada en ruta (abierta) del celular, si hay.
  int? jornadaEnRuta() {
    for (final j in jornadas) {
      final datos = (j['jornada'] as Map?) ?? const {};
      if (datos['state'] == 'abierta' && datos['id'] is int) return datos['id'] as int;
    }
    return null;
  }

  /// Ya se marcó la llegada a la visita (en Odoo o esperando en la cola).
  bool llegada(Map visita) =>
      '${visita['llegada'] ?? ''}'.isNotEmpty ||
      _pendientesDe(visita['id'] as int).any((o) => o.tipo == 'gps' && o.datos['evento'] == 'llegada');

  /// Orden del día que dejó el vendedor y aún espera en la cola (la última operación de orden manda).
  Map<int, int> _ordenEnCola(int jornadaId) {
    final ops = _pendientes.where((o) => o.tipo == 'orden' && o.datos['jornada_id'] == jornadaId).toList();
    if (ops.isEmpty) return const {};
    final ids = ((ops.last.datos['visitas'] as List?) ?? const []).whereType<int>().toList();
    return {for (var i = 0; i < ids.length; i++) ids[i]: i};
  }

  Moneda moneda(int jornadaId) => Moneda.desde(config(jornadaId)['moneda']);

  /// Id provisional (negativo) de un cliente dado de alta sin señal: se usa en pantalla hasta que Odoo crea la
  /// visita; lo que se capture para él sube con `visita_uuid`.
  static int idProvisional(String uuid) => -(int.parse(uuid.replaceAll('-', '').substring(0, 7), radix: 16) + 1);

  Iterable<Operacion> get _altas => _pendientes.where((o) => o.tipo == 'cliente_nuevo');

  Iterable<Operacion> _pendientesDe(int visitaId) {
    String? uuidAlta;
    if (visitaId < 0) {
      for (final a in _altas) {
        if (idProvisional(a.uuid) == visitaId) uuidAlta = a.uuid;
      }
    }
    return _pendientes.where(
      (o) =>
          o.tipo != 'cliente_nuevo' &&
          (o.datos['visita_id'] == visitaId || (uuidAlta != null && o.datos['visita_uuid'] == uuidAlta)),
    );
  }

  /// Devolución de [pedidoId] que espera en la cola (para no capturarla dos veces).
  Operacion? devolucionEnCola(int visitaId, int pedidoId) =>
      _pendientesDe(visitaId).where((o) => o.tipo == 'devolucion' && o.datos['pedido_id'] == pedidoId).firstOrNull;

  /// Cliente con devolución por revisar en la oficina (lo dice Odoo) o capturada que espera enviarse.
  bool tieneDevolucion(Map visita) =>
      ((visita['devoluciones'] as num?) ?? 0) > 0 ||
      _pendientesDe(visita['id'] as int).any((o) => o.tipo == 'devolucion');

  /// Motivos de devolución que bajaron con la jornada.
  List<Map> motivosDevolucion(int jornadaId) =>
      ((jornada(jornadaId)?['motivos_devolucion'] as List?) ?? const []).whereType<Map>().toList();

  /// La visita con los datos de contacto que esperan en la cola ya aplicados.
  Map _conContacto(Map visita) {
    final cambios = _pendientesDe(visita['id'] as int).where((o) => o.tipo == 'cliente').toList();
    if (cambios.isEmpty) return visita;
    final v = Map<String, Object?>.from(visita.cast<String, Object?>());
    final contacto = Map<String, Object?>.from(((v['contacto'] as Map?) ?? const {}).cast<String, Object?>());
    final fiscal = Map<String, Object?>.from(((v['fiscal'] as Map?) ?? const {}).cast<String, Object?>());
    for (final c in cambios) {
      contacto.addAll(((c.datos['contacto'] as Map?) ?? const {}).cast<String, Object?>());
      fiscal.addAll(((c.datos['fiscal'] as Map?) ?? const {}).cast<String, Object?>());
    }
    v['contacto'] = contacto;
    v['fiscal'] = fiscal;
    v['cliente'] = contacto['nombre'] ?? v['cliente'];
    v['comercial'] = contacto['comercial'] ?? v['comercial'];
    v['telefono'] = contacto['telefono'] ?? v['telefono'];
    v['direccion'] = direccionDe(contacto);
    return v;
  }

  static String direccionDe(Map contacto) => [
    contacto['calle'],
    contacto['colonia'],
    contacto['ciudad'],
  ].where((p) => p is String && p.trim().isNotEmpty).join(', ');

  /// Clientes dados de alta en el celular que aún no llegan a Odoo: se venden de contado.
  List<Map> _altasDe(int jornadaId) => [
    for (final a in _altas.where((a) => a.datos['jornada_id'] == jornadaId))
      {
        'id': idProvisional(a.uuid),
        'uuid_alta': a.uuid,
        'cliente': a.datos['nombre'] ?? 'Cliente nuevo',
        'comercial': a.datos['comercial'] ?? '',
        'telefono': a.datos['telefono'] ?? '',
        'direccion': direccionDe(a.datos),
        'contacto': {
          for (final k in ['nombre', 'comercial', 'telefono', 'correo', 'calle', 'colonia', 'ciudad', 'cp'])
            k: a.datos[k] ?? '',
          'estado': a.datos['estado'] ?? false,
          'pais': a.datos['pais'] ?? false,
        },
        'fiscal': {...((a.datos['fiscal'] as Map?) ?? const {}), 'cp': a.datos['cp'] ?? ''},
        'estado': 'pendiente',
        'secuencia': 100000,
        'alta_ruta': true,
        'fuera_de_ruta': true,
        'credito': {'a_credito': false, 'estado': 'ok'},
        'pedidos': const [],
        'codigos': const [],
      },
  ];

  /// Estado de la visita contando lo que espera en la cola.
  String estado(Map visita) {
    final id = visita['id'] as int;
    final ops = _pendientesDe(id).toList();
    final entrega = ops.where((o) => o.tipo == 'entrega').firstOrNull;
    if (entrega != null) {
      return switch (entrega.datos['resultado']) {
        'completa' => 'entregado',
        'parcial' => 'parcial',
        _ => 'no_entregado',
      };
    }
    if (ops.any((o) => o.tipo == 'pedido')) return 'pedido';
    if (ops.any((o) => o.tipo == 'sin_venta')) return 'sin_venta';
    return (visita['estado'] as String?) ?? 'pendiente';
  }

  bool enCola(Map visita) => _pendientesDe(visita['id'] as int).isNotEmpty;

  /// Visitas de la jornada: pendientes primero (en orden de visita), luego las visitadas.
  List<Map> visitas(int jornadaId) {
    final todas = [
      ...((jornada(jornadaId)?['visitas'] as List?) ?? const []).whereType<Map>().map(_conContacto),
      ..._altasDe(jornadaId).map(_conContacto),
    ];
    // Cliente nuevo que Odoo ya creó pero cuya visita aún no baja: con lo que respondió Odoo.
    for (final a in _altasHechas.values) {
      final v = a['visita'];
      if (a['jornada_id'] == jornadaId && v is Map && !todas.any((x) => x['id'] == a['visita_id'])) {
        todas.add(_conContacto({...v, 'id': a['visita_id']}));
      }
    }
    int orden(Map v) => estado(v) == 'pendiente' ? 0 : 1;
    final enCola = _ordenEnCola(jornadaId);
    int secuencia(Map v) => enCola.isNotEmpty && enCola.containsKey(v['id'])
        ? enCola[v['id']]! * 10
        : (v['secuencia'] as int? ?? 0) + (enCola.isNotEmpty ? 100000 : 0);
    todas.sort((a, b) {
      final c = orden(a) - orden(b);
      return c != 0 ? c : (secuencia(a) - secuencia(b));
    });
    return todas;
  }

  Map? visita(int jornadaId, int visitaId) {
    final id = idReal(visitaId);
    for (final v in visitas(jornadaId)) {
      if (v['id'] == id) return v;
    }
    return null;
  }

  /// El id de la visita en Odoo: un cliente nuevo ya enviado deja su id provisional por el real.
  int idReal(int visitaId) =>
      visitaId < 0 ? (_altasHechas[visitaId]?['visita_id'] as int?) ?? visitaId : visitaId;

  /// Bloqueo total (no se le vende en ruta, solo se le cobra) y su motivo, como lo manda Odoo.
  bool bloqueoTotal(Map visita) => (visita['bloqueo'] as Map?)?['total'] == true;

  String motivoBloqueo(Map visita) => '${(visita['bloqueo'] as Map?)?['motivo'] ?? ''}'.trim();

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

  /// Números del día para el tablero: lo de Odoo más lo que espera en la cola (se ve aunque no haya señal).
  Tablero tablero(int jornadaId) {
    final datos = (jornada(jornadaId)?['jornada'] as Map?) ?? const {};
    final todas = visitas(jornadaId);
    final ids = todas.map((v) => v['id']).toSet();
    final enCola = _pendientes.where((o) => ids.contains(o.datos['visita_id']));
    final estados = todas.map(estado).toList();
    return Tablero(
      // Una devolución que se aplica sola resta de lo vendido desde que se captura.
      vendido:
          _num(datos['monto']) +
          enCola.where((o) => o.tipo == 'pedido').fold(0.0, (s, o) => s + _num(o.datos['total'])) -
          enCola
              .where((o) => o.tipo == 'devolucion' && o.datos['oficina'] != true)
              .fold(0.0, (s, o) => s + _num(o.datos['monto'])),
      cobrado:
          _num(datos['cobrado']) +
          enCola
              .where((o) => o.tipo == 'cobro' || o.tipo == 'anticipo')
              .fold(0.0, (s, o) => s + _num(o.datos['monto'])),
      visitas: todas.length,
      hechas: estados.where((e) => e != 'pendiente').length,
      conPedido: estados.where((e) => e == 'pedido' || e == 'entregado' || e == 'parcial').length,
      sinVenta: estados.where((e) => e == 'sin_venta' || e == 'no_entregado').length,
    );
  }

  /// Lo que le falta al cliente para facturarle a su nombre (vacío: puede pedir factura). Cuenta lo que se
  /// modificó en el celular y aún espera en la cola. Régimen y uso solo se piden si Odoo los maneja.
  List<String> faltanFiscales(int jornadaId, Map visita) {
    final fiscal = (visita['fiscal'] as Map?) ?? const {};
    final contacto = (visita['contacto'] as Map?) ?? const {};
    final catalogos = (config(jornadaId)['catalogos_fiscales'] as Map?) ?? const {};
    final rfc = '${fiscal['rfc'] ?? ''}'.trim().toUpperCase();
    final cp = '${fiscal['cp'] is String && (fiscal['cp'] as String).isNotEmpty ? fiscal['cp'] : contacto['cp'] ?? ''}'
        .trim();
    bool usa(String clave) => ((catalogos[clave] as List?) ?? const []).isNotEmpty;
    return [
      if (rfc.isEmpty || rfcGenericos.contains(rfc)) 'RFC',
      if (cp.isEmpty) 'código postal',
      if (usa('regimen') && fiscal['regimen'] is! int) 'régimen fiscal',
      if (usa('uso') && fiscal['uso'] is! int) 'uso del CFDI',
    ];
  }

  /// Ruta de reparto: el chofer entrega los pedidos de la ruta y cobra los de contado; no levanta pedidos.
  bool esReparto(int jornadaId) => config(jornadaId)['tipo_ruta'] == 'reparto';

  /// Entregas (pedidos con sus productos) que lleva el chofer a la visita.
  List<Map> entregas(Map visita) => ((visita['entregas'] as List?) ?? const []).whereType<Map>().toList();

  /// Valor (con impuestos) de lo que se entrega de un pedido con las cantidades indicadas por ``move_id``.
  static double valorEntregado(Map entrega, Map<int, double> cantidades) => ((entrega['lineas'] as List?) ?? const [])
      .whereType<Map>()
      .fold(0.0, (s, l) => s + _num(l['precio']) * (cantidades[l['move_id']] ?? _num(l['cantidad'])));

  /// Lo que falta por cobrar al entregar un pedido de contado, contando lo que espera en la cola: una entrega en
  /// parte cobra solo lo entregado y un cobro capturado ya se descuenta.
  double porCobrarEntrega(int visitaId, Map entrega) {
    if (entrega['contado'] != true) return 0;
    final ops = _pendientesDe(visitaId).toList();
    final facturas = ((entrega['facturas'] as List?) ?? const []).toSet();
    var falta = _num(entrega['por_cobrar']);
    final op = ops.where((o) => o.tipo == 'entrega').firstOrNull;
    if (op != null) {
      if (op.datos['resultado'] == 'no') return 0;
      if (op.datos['resultado'] == 'parcial' && facturas.isEmpty) {
        final cantidades = <int, double>{
          for (final l in ((op.datos['lineas'] as List?) ?? const []).whereType<Map>())
            l['move_id'] as int: _num(l['cantidad']),
        };
        for (final l in ((entrega['lineas'] as List?) ?? const []).whereType<Map>()) {
          cantidades.putIfAbsent(l['move_id'] as int, () => 0);
        }
        final pagado = _num(entrega['total']) - _num(entrega['por_cobrar']);
        falta = math.max(0, valorEntregado(entrega, cantidades) - pagado);
      }
    }
    for (final o in ops) {
      final esDelPedido =
          (o.tipo == 'anticipo' && o.datos['pedido_id'] == entrega['pedido_id']) ||
          (o.tipo == 'cobro' &&
              facturas.isNotEmpty &&
              ((o.datos['factura_ids'] as List?) ?? const []).any(facturas.contains));
      if (esDelPedido) falta -= _num(o.datos['monto']);
    }
    return math.max(0, falta);
  }

  /// Datos de las tarjetas del inicio que manda Odoo: meta de la ruta y las últimas jornadas.
  Map tableroOdoo(int jornadaId) => (jornada(jornadaId)?['tablero'] as Map?) ?? const {};

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
    0.0,
    (s, l) => s + precio(visitaId, l.producto, uomId: l.uomId) * l.cantidad * factorIva(l.productId),
  );

  /// Texto de búsqueda de cada producto, ya en minúsculas (con miles de productos no se arma en cada tecla).
  late final List<String> _textos = [
    for (final p in catalogo) '${p['name']} ${p['code']} ${p['plantilla_nombre'] ?? ''}'.toLowerCase(),
  ];

  /// Variantes de cada plantilla (productos con atributos), en el orden del catálogo.
  late final Map<int, List<Map>> _variantes = () {
    final r = <int, List<Map>>{};
    for (final p in catalogo) {
      final t = p['plantilla'];
      if (t is int && ((p['atributos'] as List?) ?? const []).isNotEmpty) r.putIfAbsent(t, () => []).add(p);
    }
    return r;
  }();

  /// Las variantes del mismo producto que [producto] (él incluido); vacío si no tiene atributos.
  List<Map> variantes(Map producto) {
    final t = producto['plantilla'];
    final lista = t is int ? _variantes[t] : null;
    return lista != null && lista.length > 1 ? lista : const [];
  }

  /// Busca por nombre, clave o código de barras. Un código de barras exacto devuelve también su embalaje.
  /// Con [limite] productos; las variantes de un producto cuentan como uno.
  List<Map> buscar(String texto, {int limite = 80}) {
    final t = texto.trim().toLowerCase();
    final codigo = texto.trim();
    final r = <Map>[];
    final grupos = <int>{};
    var tarjetas = 0;
    for (var i = 0; i < catalogo.length; i++) {
      final p = catalogo[i];
      if (t.isNotEmpty && !_textos[i].contains(t) && !((p['barcodes'] as Map?) ?? const {}).containsKey(codigo)) {
        continue;
      }
      final nueva = variantes(p).isEmpty || grupos.add(p['plantilla'] as int);
      if (nueva) {
        if (tarjetas == limite) break;
        tarjetas++;
      }
      r.add(p);
    }
    return r;
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
