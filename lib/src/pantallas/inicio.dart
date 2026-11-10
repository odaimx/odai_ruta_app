import 'package:flutter/material.dart';

import '../actualizar.dart';
import '../api.dart';
import '../base_local.dart';
import '../motor.dart';
import '../version.dart';
import 'pin.dart';
import 'ruta.dart';

String _fechaLocal(DateTime? utc) {
  if (utc == null) return 'nunca';
  final l = utc.toLocal();
  String dos(int n) => n.toString().padLeft(2, '0');
  return '${dos(l.day)}/${dos(l.month)} ${dos(l.hour)}:${dos(l.minute)}';
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
    if (mounted) {
      setState(() {
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
    return Scaffold(
      appBar: AppBar(
        leading: Padding(
          padding: const EdgeInsets.only(left: 12),
          child: Image.asset('assets/logo_blanco.png', fit: BoxFit.contain),
        ),
        leadingWidth: 76,
        title: Text(motor.nombreVendedor.isEmpty ? 'Odai Ruta' : motor.nombreVendedor),
        actions: [
          IconButton(
            tooltip: 'Cambiar mi PIN',
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PantallaNuevoPin(motor: motor))),
            icon: const Icon(Icons.password),
          ),
          IconButton(
            tooltip: 'Bloquear',
            onPressed: motor.pin == null ? null : motor.bloquearPantalla,
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => motor.sincronizar(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (motor.actualizacion != null) _TarjetaActualizar(motor: motor),
            if (aviso != null) _Aviso(texto: aviso, color: tema.colorScheme.errorContainer),
            if (motor.nivelLicencia == 'aviso' && motor.mensajeLicencia.isNotEmpty)
              _Aviso(texto: motor.mensajeLicencia, color: tema.colorScheme.tertiaryContainer),
            if (motor.ultimoError != null) _Aviso(texto: motor.ultimoError!, color: tema.colorScheme.surfaceContainerHighest),
            Card(
              child: ListTile(
                leading: motor.sincronizando
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 3))
                    : Icon(motor.pendientes == 0 ? Icons.cloud_done : Icons.cloud_upload),
                title: Text(motor.pendientes == 0
                    ? 'Todo enviado'
                    : motor.pendientes == 1
                        ? '1 movimiento por enviar'
                        : '${motor.pendientes} movimientos por enviar'),
                subtitle: Text('Última sincronización: ${_fechaLocal(motor.ultimaSync)}'),
                trailing: IconButton(
                  tooltip: 'Sincronizar',
                  onPressed: motor.sincronizando ? null : () => motor.sincronizar(),
                  icon: const Icon(Icons.sync),
                ),
              ),
            ),
            for (final op in _porRevisar)
              Card(
                color: tema.colorScheme.errorContainer,
                child: ListTile(
                  leading: const Icon(Icons.report),
                  title: Text(op.estado == EstadoCola.rechazado ? 'Odoo no aceptó un ${op.tipo}' : 'No se pudo enviar un ${op.tipo}'),
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
            const SizedBox(height: 8),
            Text('Mis jornadas', style: tema.textTheme.titleMedium),
            if (_jornadas.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('No hay jornadas abiertas en el celular. Conéctese a internet y sincronice; si sigue '
                    'sin aparecer, pida al supervisor que revise su ruta.'),
              ),
            for (final datos in _jornadas) _TarjetaJornada(motor: motor, datos: datos),
            const SizedBox(height: 24),
            Center(child: Text('Versión $appVersionCompleta', style: tema.textTheme.bodySmall)),
          ],
        ),
      ),
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
  const _TarjetaJornada({required this.motor, required this.datos});

  final Motor motor;
  final Map datos;

  @override
  Widget build(BuildContext context) {
    final jornada = (datos['jornada'] as Map?) ?? const {};
    final visitas = ((datos['visitas'] as List?) ?? const []).whereType<Map>().toList();
    final pendientes = visitas.where((v) => v['state'] == 'pendiente').length;
    return Card(
      child: ListTile(
        leading: const Icon(Icons.route),
        title: Text('${jornada['ruta'] ?? jornada['name'] ?? ''}'),
        subtitle: Text('${jornada['fecha'] ?? ''} · ${visitas.length} clientes · $pendientes por visitar'
            '${jornada['state'] == 'abierta' ? '' : ' · cerrada'}'),
        trailing: const Icon(Icons.chevron_right),
        onTap: jornada['id'] is! int
            ? null
            : () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => PantallaRuta(motor: motor, jornadaId: jornada['id'] as int))),
      ),
    );
  }
}
