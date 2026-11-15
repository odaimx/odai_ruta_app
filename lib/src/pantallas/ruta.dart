import 'package:flutter/material.dart';

import '../motor.dart';
import '../ruta.dart';
import 'cliente.dart';
import '../tema.dart';
import 'cliente_datos.dart';
import 'entrega.dart';
import 'mapa_ruta.dart';
import 'comun.dart';
import 'pedido.dart';

/// Los clientes de la jornada: primero los que faltan por visitar.
class PantallaRuta extends StatefulWidget {
  const PantallaRuta({super.key, required this.motor, required this.jornadaId});

  final Motor motor;
  final int jornadaId;

  @override
  State<PantallaRuta> createState() => _PantallaRutaState();
}

class _PantallaRutaState extends State<PantallaRuta> {
  Ruta? _ruta;
  String _filtro = '';
  final _buscar = TextEditingController();

  /// Pendientes (por omisión), visitados o todos: los visitados no estorban al buscar.
  String _vista = 'pendientes';

  /// Lista (como siempre) o mapa; el celular recuerda la última elección del vendedor.
  bool _mapa = false;

  /// Cambiar el orden de visita del día con flechas.
  bool _ordenando = false;

  @override
  void initState() {
    super.initState();
    widget.motor.addListener(_cargar);
    _cargar();
    widget.motor.dato('vista_ruta').then((v) {
      if (mounted && v == 'mapa') setState(() => _mapa = true);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _avisoUbicacion());
  }

  /// La primera vez en la jornada: aviso de que se registra la ubicación (y Android pide el permiso).
  Future<void> _avisoUbicacion() async {
    final motor = widget.motor;
    final clave = 'aviso_ubicacion_${widget.jornadaId}';
    if (await motor.dato(clave) == true) {
      motor.revisarRecorrido();
      return;
    }
    final ruta = await Ruta.cargar(motor);
    if (!ruta.seguimiento(widget.jornadaId)) return;
    final aviso = '${ruta.mapa(widget.jornadaId)['aviso'] ?? ''}'.trim();
    final abierta = (ruta.jornada(widget.jornadaId)?['jornada'] as Map?)?['state'] == 'abierta';
    if (aviso.isEmpty || !abierta || !mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ubicación durante la jornada'),
        content: Text(aviso, key: const ValueKey('aviso_ubicacion')),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Entendido'))],
      ),
    );
    await motor.base?.escribir(clave, true);
    await motor.ubicador?.actual();
    motor.revisarRecorrido();
  }

  Future<void> _cambiarVista(bool mapa) async {
    setState(() {
      _mapa = mapa;
      _ordenando = false;
    });
    await widget.motor.base?.escribir('vista_ruta', mapa ? 'mapa' : 'lista');
  }

  /// Sube o baja un cliente en el orden de visita del día (no cambia la ruta: eso lo decide el supervisor).
  Future<void> _mover(List<Map> todas, Map v, int paso) async {
    final ids = [for (final x in todas) x['id'] as int];
    final i = ids.indexOf(v['id'] as int);
    final j = i + paso;
    if (i < 0 || j < 0 || j >= ids.length) return;
    ids[i] = ids[j];
    ids[j] = v['id'] as int;
    await widget.motor.registrar('orden', {
      'jornada_id': widget.jornadaId,
      'visitas': ids.where((id) => id > 0).toList(),
    });
    await _cargar();
  }

  @override
  void dispose() {
    widget.motor.removeListener(_cargar);
    _buscar.dispose();
    super.dispose();
  }

  /// Tocar un cliente lleva directo a levantar el pedido (con la jornada cerrada, a su ficha).
  Future<void> _abrir(Map v, bool abierta) async {
    final id = v['id'] as int;
    // Llegada automática al abrir al cliente si no se marcó con "Llegué".
    if (abierta && _ruta != null && _ruta!.estado(v) == 'pendiente' && !_ruta!.llegada(v)) {
      widget.motor.marcarVisita(id, 'llegada');
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _ruta?.esReparto(widget.jornadaId) == true
            ? PantallaEntrega(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: id)
            : abierta
            ? PantallaPedido(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: id)
            : PantallaCliente(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: id),
      ),
    );
    _cargar();
  }

  /// Escanear el código del cliente (su clave o código de barras) para encontrarlo.
  Future<void> _escanear() async {
    final codigo = await escanear(context, titulo: 'Escanear cliente');
    if (codigo == null || !mounted) return;
    _buscar.text = codigo;
    setState(() {
      _filtro = codigo;
      _vista = 'todos';
    });
  }

  Future<void> _clienteNuevo() async {
    final id = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaDatosCliente(motor: widget.motor, jornadaId: widget.jornadaId),
      ),
    );
    await _cargar();
    if (id == null || !mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PantallaPedido(motor: widget.motor, jornadaId: widget.jornadaId, visitaId: id),
      ),
    );
    _cargar();
  }

  Future<void> _cargar() async {
    final ruta = await Ruta.cargar(widget.motor);
    if (mounted) setState(() => _ruta = ruta);
  }

  Future<void> _cerrar() async {
    final ruta = _ruta!;
    final pendientes = ruta.visitas(widget.jornadaId).where((v) => ruta.estado(v) == 'pendiente').length;
    final reparto = ruta.esReparto(widget.jornadaId);
    if (pendientes > 0 && ruta.config(widget.jornadaId)['cerrar_pendientes'] != true) {
      avisar(
        context,
        reparto
            ? 'Faltan $pendientes clientes. Registre la entrega o márquela como no entregada.'
            : 'Faltan $pendientes clientes. Levante el pedido o indique el motivo de no venta.',
        error: true,
      );
      return;
    }
    final ok = await confirmar(
      context,
      'Cerrar jornada',
      pendientes > 0
          ? 'Quedan $pendientes clientes sin visitar; se marcarán como no visitados. Después ya no podrá '
                '${reparto ? 'entregar' : 'vender'} en esta jornada.'
          : 'Después ya no podrá ${reparto ? 'entregar' : 'vender'} en esta jornada.',
      si: 'Cerrar',
    );
    if (!ok || !mounted) return;
    try {
      await widget.motor.registrar('cerrar', {'jornada_id': widget.jornadaId});
      if (mounted) {
        avisar(context, 'Cierre guardado. Se enviará a Odoo con lo demás.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) avisar(context, textoError(e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ruta = _ruta;
    final datos = ruta?.jornada(widget.jornadaId);
    if (ruta == null || datos == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final jornada = datos['jornada'] as Map;
    final moneda = ruta.moneda(widget.jornadaId);
    final t = _filtro.toLowerCase();
    final todas = ruta.visitas(widget.jornadaId);
    final visitas = todas
        .where(
          (v) => switch (_vista) {
            'pendientes' => ruta.estado(v) == 'pendiente',
            'visitados' => ruta.estado(v) != 'pendiente',
            _ => true,
          },
        )
        .where(
          (v) =>
              t.isEmpty ||
              '${v['cliente']} ${v['comercial']} ${(v['codigos'] as List?)?.join(' ')}'.toLowerCase().contains(t),
        )
        .toList();
    final aviso = datos['licencia_aviso'] as String?;
    final abierta = jornada['state'] == 'abierta';
    final pendientesN = todas.where((v) => ruta.estado(v) == 'pendiente').length;
    final reparto = ruta.esReparto(widget.jornadaId);
    return Scaffold(
      appBar: CabeceraOdai(
        titulo: widget.motor.nombreVendedor.isEmpty ? '${jornada['ruta']}' : widget.motor.nombreVendedor,
        subtitulo: '${jornada['ruta']}',
      ),
      bottomNavigationBar: const PieOdai(),
      body: Column(
        children: [
          BarraAcciones(
            motor: widget.motor,
            acciones: [
              if (abierta && !reparto) Accion(Icons.person_add, 'Nuevo cliente', _clienteNuevo, principal: true),
              Accion(
                Icons.sync,
                widget.motor.sincronizando ? 'Sincronizando...' : 'Sincronizar',
                widget.motor.sincronizando ? null : () => widget.motor.sincronizar(),
              ),
              if (abierta) Accion(Icons.flag, 'Cerrar jornada', _cerrar),
            ],
          ),
          if (aviso != null && aviso.isNotEmpty)
            MaterialBanner(content: Text(aviso), actions: const [SizedBox.shrink()]),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
            child: Buscador(
              controller: _buscar,
              hint: 'Buscar cliente',
              onChanged: (v) => setState(() => _filtro = v),
              onEscanear: _escanear,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6, right: 8),
            child: Row(
              children: [
                Expanded(
                  child: Filtros<String>(
                    opciones: [
                      ('pendientes', 'Pendientes  $pendientesN'),
                      ('visitados', 'Visitados  ${todas.length - pendientesN}'),
                      ('todos', 'Todos  ${todas.length}'),
                    ],
                    elegido: _vista,
                    onChanged: (v) => setState(() => _vista = v),
                  ),
                ),
                if (!_mapa && abierta && _vista == 'pendientes' && t.isEmpty)
                  IconButton(
                    key: const ValueKey('ordenar'),
                    tooltip: _ordenando ? 'Listo' : 'Cambiar orden de visita',
                    isSelected: _ordenando,
                    onPressed: () => setState(() => _ordenando = !_ordenando),
                    icon: const Icon(Icons.swap_vert, size: 28, color: Color(0xFF111111)),
                    selectedIcon: const Icon(Icons.check_circle, size: 28, color: moradoOdai),
                  ),
                IconButton(
                  key: const ValueKey('vista_mapa'),
                  tooltip: _mapa ? 'Ver lista' : 'Ver mapa',
                  onPressed: () => _cambiarVista(!_mapa),
                  icon: Icon(_mapa ? Icons.view_list : Icons.map_outlined, size: 28, color: moradoOscuro),
                ),
              ],
            ),
          ),
          if (_mapa)
            Expanded(
              child: MapaRuta(
                motor: widget.motor,
                ruta: ruta,
                jornadaId: widget.jornadaId,
                visitas: visitas,
                onAbrir: (v) => _abrir(v, abierta),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                itemCount: visitas.length,
                itemBuilder: (context, i) {
                  final v = visitas[i];
                  final estado = ruta.estado(v);
                  final porCobrar = ruta.porCobrar(v['id'] as int);
                  final comercial = '${v['comercial'] ?? ''}'.trim();
                  final bloqueado = (v['credito'] as Map?)?['estado'] == 'block';
                  final chico = Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF222222));
                  return TarjetaOdai(
                    key: ValueKey('cliente_${v['id']}'),
                    padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                    onTap: _ordenando ? null : () => _abrir(v, abierta),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                comercial.isNotEmpty ? comercial : '${v['cliente']}',
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF111111),
                                ),
                              ),
                              if (comercial.isNotEmpty)
                                Text('${v['cliente']}', style: const TextStyle(fontSize: 16, color: Color(0xFF222222))),
                              if (porCobrar > 0) Text('Debe ${moneda(porCobrar)}', style: chico),
                              if (reparto)
                                Text(
                                  '${ruta.entregas(v).length == 1 ? '1 pedido' : '${ruta.entregas(v).length} pedidos'}'
                                  ' · ${moneda(ruta.entregas(v).fold(0.0, (s, e) => s + ((e['total'] as num?)?.toDouble() ?? 0)))}',
                                  style: chico,
                                ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(etiquetasEstado[estado] ?? estado, style: chico),
                            if (ruta.enCola(v)) Text('por enviar', style: chico),
                            if (bloqueado)
                              const Tooltip(
                                message: 'Crédito bloqueado',
                                child: Icon(Icons.credit_card_off, size: 18, color: Color(0xFFE53935)),
                              ),
                          ],
                        ),
                        const SizedBox(width: 6),
                        if (_ordenando) ...[
                          IconButton(
                            key: ValueKey('subir_${v['id']}'),
                            tooltip: 'Subir',
                            onPressed: i == 0 ? null : () => _mover(visitas, v, -1),
                            icon: const Icon(Icons.arrow_upward, size: 26),
                          ),
                          IconButton(
                            key: ValueKey('bajar_${v['id']}'),
                            tooltip: 'Bajar',
                            onPressed: i == visitas.length - 1 ? null : () => _mover(visitas, v, 1),
                            icon: const Icon(Icons.arrow_downward, size: 26),
                          ),
                        ] else
                          Icon(
                            estado == 'pendiente'
                                ? Icons.keyboard_double_arrow_right
                                : estado == 'pedido'
                                ? Icons.shopping_cart
                                : estado == 'entregado' || estado == 'parcial'
                                ? Icons.local_shipping
                                : Icons.block,
                            size: 30,
                            color: estado == 'pendiente' ? const Color(0xFF111111) : moradoOscuro,
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
