import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../actualizar.dart';
import '../api.dart';
import '../base_local.dart';
import '../motor.dart';
import '../ruta.dart';
import '../tema.dart';
import 'comun.dart';
import 'pin.dart';
import 'ruta.dart';

String _fechaLocal(DateTime? utc) {
  if (utc == null) return 'nunca';
  final l = utc.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(l.day)}/${dos(l.month)}/${dos(l.year % 100)} ${dos(l.hour)}:${dos(l.minute)}';
}

/// "2026-11-12" → "12/11/26".
String fechaCorta(Object? fecha) {
  final p = '${fecha ?? ''}'.split('-');
  return p.length == 3 ? '${p[2]}/${p[1]}/${p[0].substring(p[0].length - 2)}' : '${fecha ?? ''}';
}

/// Inicio del vendedor: sus jornadas, si puede vender, lo que espera subir y lo que Odoo rechazó.
class PantallaInicio extends StatefulWidget {
  const PantallaInicio({super.key, required this.motor});

  final Motor motor;

  @override
  State<PantallaInicio> createState() => _PantallaInicioState();
}

class _PantallaInicioState extends State<PantallaInicio> {
  List<Map> _jornadas = const [];
  List<Operacion> _porRevisar = const [];
  Ruta? _ruta;

  @override
  void initState() {
    super.initState();
    widget.motor.addListener(_cargar);
    _cargar();
  }

  @override
  void dispose() {
    widget.motor.removeListener(_cargar);
    super.dispose();
  }

  Future<void> _cargar() async {
    final jornadas = ((await widget.motor.dato('jornadas')) as List?)?.whereType<Map>().toList() ?? const [];
    final revisar = await widget.motor.cola?.porRevisar() ?? const <Operacion>[];
    final ruta = await Ruta.cargar(widget.motor);
    if (mounted) {
      setState(() {
        _ruta = ruta;
        _jornadas = jornadas;
        _porRevisar = revisar;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final motor = widget.motor;
    final tema = Theme.of(context);
    final aviso = motor.motivoNoVender;
    final ruta = _ruta;
    final abiertas = _jornadas.where((d) => (d['jornada'] as Map?)?['state'] == 'abierta').toList();
    final principal = (abiertas.isNotEmpty ? abiertas : _jornadas).firstOrNull;
    final principalId = (principal?['jornada'] as Map?)?['id'];
    return Scaffold(
      appBar: CabeceraOdai(titulo: motor.nombreVendedor.isEmpty ? 'Odai Ruta' : motor.nombreVendedor),
      bottomNavigationBar: const PieOdai(),
      body: Column(children: [
        BarraAcciones(motor: motor, acciones: [
          // Sincronizar ya está en la tarjeta de abajo; "Actualizar" queda al final del menú.
          if (motor.pin != null) Accion(Icons.lock, 'Bloquear', motor.bloquearPantalla, principal: true),
          Accion(Icons.password, 'Cambiar mi PIN',
              () => Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaNuevoPin(motor: motor)))),
        ]),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () => motor.sincronizar(),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              children: [
                if (motor.actualizacion != null) _TarjetaActualizar(motor: motor),
                if (aviso != null) _Aviso(texto: aviso, color: tema.colorScheme.errorContainer),
                if (motor.nivelLicencia == 'aviso' && motor.mensajeLicencia.isNotEmpty)
                  _Aviso(texto: motor.mensajeLicencia, color: lavanda),
                if (motor.ultimoError != null) _Aviso(texto: motor.ultimoError!, color: Colors.white),
                _TarjetaSync(motor: motor),
                for (final op in _porRevisar)
                  Card(
                    color: tema.colorScheme.errorContainer,
                    child: ListTile(
                      leading: const Icon(Icons.report),
                      title: Text(op.estado == EstadoCola.rechazado
                          ? 'Odoo no aceptó un ${op.tipo}'
                          : 'No se pudo enviar un ${op.tipo}'),
                      subtitle: Text(op.mensaje ?? ''),
                      trailing: IconButton(
                        tooltip: 'Enterado',
                        icon: const Icon(Icons.check),
                        onPressed: () async {
                          await motor.cola?.marcarVista(op.uuid);
                          _cargar();
                        },
                      ),
                    ),
                  ),
                if (_jornadas.isEmpty)
                  const TarjetaOdai(
                    child: Text('No hay jornadas abiertas en el celular. Conéctese a internet y sincronice; si sigue '
                        'sin aparecer, pida al supervisor que revise su ruta.'),
                  ),
                for (final datos in _jornadas) _TarjetaJornada(motor: motor, datos: datos, ruta: ruta),
                if (ruta != null && principalId is int) _Tablero(ruta: ruta, jornadaId: principalId),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _TarjetaSync extends StatelessWidget {
  const _TarjetaSync({required this.motor});

  final Motor motor;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return TarjetaOdai(
      child: Row(children: [
        SizedBox(
          width: 44,
          child: motor.sincronizando
              ? const Center(child: SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 3)))
              : Icon(motor.pendientes == 0 ? Icons.cloud_done : Icons.cloud_upload, size: 34, color: moradoOscuro),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                motor.pendientes == 0
                    ? 'Todo enviado'
                    : motor.pendientes == 1
                        ? '1 movimiento por enviar'
                        : '${motor.pendientes} movimientos por enviar',
                style: tema.textTheme.headlineSmall),
            Text('Última sincronización:\n${_fechaLocal(motor.ultimaSync)}', style: tema.textTheme.bodyMedium),
          ]),
        ),
        SizedBox(
          width: 54,
          height: 50,
          child: OutlinedButton(
            key: const ValueKey('sync_tarjeta'),
            onPressed: motor.sincronizando ? null : () => motor.sincronizar(),
            style: OutlinedButton.styleFrom(backgroundColor: lavanda, padding: EdgeInsets.zero),
            child: const Icon(Icons.sync, size: 30, color: Color(0xFF111111)),
          ),
        ),
      ]),
    );
  }
}

/// Tablero del inicio, estilo BI: proyección (meta de la oficina), visitas, ruta actual y últimas rutas.
class _Tablero extends StatelessWidget {
  const _Tablero({required this.ruta, required this.jornadaId});

  final Ruta ruta;
  final int jornadaId;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final moneda = ruta.moneda(jornadaId);
    final hoy = ruta.tablero(jornadaId);
    final odoo = ruta.tableroOdoo(jornadaId);
    final monto = ((ruta.jornada(jornadaId)?['jornada'] as Map?)?['monto'] as num?)?.toDouble() ?? 0;
    final meta = (odoo['meta'] as num?)?.toDouble() ?? 0;
    final meses = (odoo['meses'] as num?)?.toInt() ?? 0;
    // Lo vendido en el periodo de la meta más lo de hoy que aún espera en el celular.
    final ejecutado = ((odoo['ejecutado'] as num?)?.toDouble() ?? 0) + (hoy.vendido - monto);
    final ultimas = ((odoo['ultimas'] as List?) ?? const []).whereType<Map>().toList();
    String corto(num v) => moneda(v).replaceAll(RegExp(r'\.00$'), '');

    final titulo = tema.textTheme.titleMedium?.copyWith(color: moradoOscuro, fontWeight: FontWeight.w700);
    const gris = TextStyle(fontSize: 13, color: Color(0xFF555555));
    const cifra = TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF111111));

    Widget tarjeta(Widget hijo, {Key? key}) =>
        TarjetaOdai(key: key, margen: const EdgeInsets.all(4), padding: const EdgeInsets.all(12), child: hijo);
    Widget dato(String etiqueta, String valor, {Color? color}) => Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(etiqueta, style: gris),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(valor, style: cifra.copyWith(color: color)),
            ),
          ]),
        );

    final avanceMeta = meta > 0 ? ejecutado / meta : 0.0;
    final proyeccion = tarjeta(
      key: const ValueKey('tablero_proyeccion'),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Proyección', style: titulo),
        Text(meta > 0 ? 'Meta a $meses ${meses == 1 ? 'mes' : 'meses'}' : 'Sin meta de la oficina', style: gris),
        const SizedBox(height: 8),
        Center(child: Anillo(valor: avanceMeta, color: avanceMeta >= 1 ? verdeOdai : moradoOdai)),
        const SizedBox(height: 8),
        if (meta > 0) dato('Meta', corto(meta)),
        dato('Ejecutado', corto(ejecutado), color: moradoOdai),
        if (meta > 0 && ejecutado < meta) dato('Falta', corto(meta - ejecutado)),
      ]),
    );

    final efectividad = hoy.hechas == 0 ? 0 : (100 * hoy.conPedido / hoy.hechas).round();
    final reparto = ruta.esReparto(jornadaId);
    final visitas = tarjeta(
      key: const ValueKey('tablero_visitas'),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Visitas', style: titulo),
        Text(hoy.pendientes == 0 ? 'Ruta completa' : '${hoy.pendientes} por visitar', style: gris),
        const SizedBox(height: 8),
        Center(
          child: Anillo(
            valor: hoy.visitas == 0 ? 0 : hoy.hechas / hoy.visitas,
            centro: Text('${hoy.hechas}/${hoy.visitas}', style: cifra),
          ),
        ),
        const SizedBox(height: 8),
        dato(reparto ? 'Entregados' : 'Con pedido', '${hoy.conPedido}', color: verdeOdai),
        dato(reparto ? 'No entregados' : 'Sin venta', '${hoy.sinVenta}', color: const Color(0xFFE53935)),
        dato('Efectividad', '$efectividad%'),
      ]),
    );

    final cobrado = hoy.vendido > 0 ? hoy.cobrado / hoy.vendido : 0.0;
    final actual = tarjeta(
      key: const ValueKey('tablero_actual'),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ruta actual', style: titulo),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: dato('Vendido', moneda(hoy.vendido), color: moradoOdai)),
          Expanded(child: dato('Cobrado', moneda(hoy.cobrado), color: azulOdai)),
          Expanded(child: dato('Por cobrar', moneda(math.max(0, hoy.vendido - hoy.cobrado)))),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: BarraAvance(valor: cobrado, azul: true, alto: 12)),
          const SizedBox(width: 8),
          Text('${(cobrado * 100).round()}% cobrado', style: gris),
        ]),
      ]),
    );

    // Últimas rutas: barras horizontales con el importe a un lado, de la más antigua a la de hoy.
    final barras = [
      for (final (i, u) in ultimas.reversed.indexed)
        (etiqueta: (ultimas.length - i).toString().padLeft(2, '0'), monto: (u['monto'] as num?)?.toDouble() ?? 0, hoy: false),
      (etiqueta: 'Hoy', monto: hoy.vendido, hoy: true),
    ];
    final maximo = barras.fold(0.0, (m, b) => b.monto > m ? b.monto : m);
    final promedio = ultimas.isEmpty ? null : ultimas.fold(0.0, (t, u) => t + ((u['monto'] as num?)?.toDouble() ?? 0)) / ultimas.length;
    final historial = tarjeta(
      key: const ValueKey('tablero_ultimas'),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Últimas rutas', style: titulo),
        if (promedio != null) Text('Promedio ${moneda(promedio)}', style: gris),
        const SizedBox(height: 8),
        for (final b in barras)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 36, child: Text(b.etiqueta, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: maximo <= 0 ? 0.02 : math.max(0.02, b.monto / maximo),
                    child: Container(
                      height: 18,
                      decoration: BoxDecoration(
                        color: b.hoy ? verdeOdai : azulOdai,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 104,
                child: Text(moneda(b.monto),
                    key: ValueKey('ultima_${b.etiqueta}'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
      ]),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(children: [
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: proyeccion),
            Expanded(child: visitas),
          ]),
        ),
        actual,
        historial,
      ]),
    );
  }
}

class _TarjetaActualizar extends StatefulWidget {
  const _TarjetaActualizar({required this.motor});

  final Motor motor;

  @override
  State<_TarjetaActualizar> createState() => _TarjetaActualizarState();
}

class _TarjetaActualizarState extends State<_TarjetaActualizar> {
  bool _bajando = false;
  double? _avance;
  String? _mensaje;

  Future<void> _actualizar() async {
    setState(() {
      _bajando = true;
      _avance = null;
      _mensaje = null;
    });
    try {
      final r = await actualizarApp(widget.motor, avance: (a) {
        if (mounted) setState(() => _avance = a);
      });
      if (mounted && r == 'permiso') {
        setState(() => _mensaje = 'Permita "Instalar apps de esta fuente", regrese y toque Actualizar otra vez.');
      }
    } on SinSenal {
      if (mounted) setState(() => _mensaje = 'Sin señal. Intente donde haya internet (mejor con wifi).');
    } on ApiError catch (e) {
      if (mounted) setState(() => _mensaje = e.mensaje);
    } catch (e) {
      if (mounted) setState(() => _mensaje = 'No se pudo actualizar: $e');
    } finally {
      if (mounted) setState(() => _bajando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final version = widget.motor.actualizacion!;
    final tema = Theme.of(context);
    final notas = '${version['notas'] ?? ''}'.trim();
    return Card(
      color: tema.colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Hay una versión nueva: ${version['version']}', style: tema.textTheme.titleMedium),
          if (notas.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(notas)),
          if (version['obligatoria'] == true)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text('Es obligatoria: actualice para seguir vendiendo.', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          const SizedBox(height: 8),
          if (_bajando) ...[
            LinearProgressIndicator(value: _avance),
            const SizedBox(height: 4),
            Text(_avance == null ? 'Descargando...' : 'Descargando ${(_avance! * 100).round()}%'),
          ] else
            FilledButton.icon(onPressed: _actualizar, icon: const Icon(Icons.system_update), label: const Text('Actualizar')),
          if (_mensaje != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_mensaje!)),
          const SizedBox(height: 4),
          Text('Lo guardado en el celular no se pierde.', style: tema.textTheme.bodySmall),
        ]),
      ),
    );
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      Card(color: color, child: Padding(padding: const EdgeInsets.all(12), child: Text(texto)));
}

class _TarjetaJornada extends StatelessWidget {
  const _TarjetaJornada({required this.motor, required this.datos, this.ruta});

  final Motor motor;
  final Map datos;
  final Ruta? ruta;

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final jornada = (datos['jornada'] as Map?) ?? const {};
    final id = jornada['id'];
    // Con la cola aplicada (un cliente dado de alta sin señal ya cuenta).
    final visitas = id is int && ruta != null
        ? ruta!.visitas(id)
        : ((datos['visitas'] as List?) ?? const []).whereType<Map>().toList();
    final pendientes = ruta != null && id is int
        ? visitas.where((v) => ruta!.estado(v) == 'pendiente').length
        : visitas.where((v) => v['estado'] == 'pendiente').length;
    String dos(int n) => n.toString().padLeft(2, '0');
    return TarjetaOdai(
      onTap: id is! int
          ? null
          : () => Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaRuta(motor: motor, jornadaId: id))),
      child: Row(children: [
        const SizedBox(width: 44, child: Icon(Icons.route, size: 32, color: moradoOscuro)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${jornada['ruta'] ?? jornada['name'] ?? ''}', style: tema.textTheme.headlineSmall),
            Text(
                '${fechaCorta(jornada['fecha'])}    ${dos(visitas.length)} Clientes    $pendientes por visitar'
                '${jornada['state'] == 'abierta' ? '' : '    cerrada'}',
                style: tema.textTheme.bodyMedium),
            // Jornada de más días que la ruta (y avisos de licencia) en naranja, debajo de la ruta.
            if ('${datos['licencia_aviso'] ?? ''}'.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('${datos['licencia_aviso']}'.trim(),
                    key: ValueKey('aviso_jornada_$id'),
                    style: const TextStyle(fontSize: 14, color: naranjaOdai, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
        const Icon(Icons.keyboard_double_arrow_right, size: 34, color: Color(0xFF111111)),
      ]),
    );
  }
}
