import 'package:flutter/material.dart';

import '../base_local.dart';
import '../motor.dart';

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
        title: Text(motor.nombreVendedor.isEmpty ? 'Odai Ruta' : motor.nombreVendedor),
        actions: [
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
            for (final datos in _jornadas) _TarjetaJornada(datos: datos),
          ],
        ),
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
  const _TarjetaJornada({required this.datos});

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
        subtitle: Text('${jornada['fecha'] ?? ''} · ${visitas.length} clientes · $pendientes por visitar'),
      ),
    );
  }
}
