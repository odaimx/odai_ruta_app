import 'package:flutter/material.dart';

import '../actualizar.dart';
import '../api.dart';
import '../motor.dart';
import '../tema.dart';
import 'comun.dart';

/// Odoo pide una versión mayor: la app no deja trabajar hasta actualizar. Antes sube lo que espera en el celular,
/// para que nada se quede atrás.
class PantallaActualizarObligatoria extends StatefulWidget {
  const PantallaActualizarObligatoria({super.key, required this.motor});

  final Motor motor;

  @override
  State<PantallaActualizarObligatoria> createState() => _PantallaActualizarObligatoriaState();
}

class _PantallaActualizarObligatoriaState extends State<PantallaActualizarObligatoria> {
  bool _bajando = false;
  double? _avance;
  String? _mensaje;

  Future<void> _actualizar() async {
    final motor = widget.motor;
    setState(() {
      _bajando = true;
      _avance = null;
      _mensaje = null;
    });
    try {
      // Lo pendiente sube primero; si no hay señal no se puede descargar de todos modos.
      if (motor.pendientes > 0) await motor.sincronizar();
      if (motor.pendientes > 0) {
        setState(() => _mensaje = 'Aún hay ${motor.pendientes} movimientos por enviar. Busque señal y vuelva a intentar.');
        return;
      }
      final r = await actualizarApp(motor, avance: (a) {
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
    return ListenableBuilder(
      listenable: widget.motor,
      builder: (context, _) {
        final motor = widget.motor;
        final version = motor.actualizacion;
        final notas = '${version?['notas'] ?? ''}'.trim();
        return Scaffold(
          appBar: CabeceraOdai(titulo: 'Actualice la app', subtitulo: 'Versión ${motor.versionMinima} o mayor'),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Icon(Icons.system_update, size: 72, color: moradoOdai),
              const SizedBox(height: 12),
              const Text('Hay una versión nueva obligatoria',
                  key: ValueKey('actualizar_obligatoria'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: moradoOscuro)),
              const SizedBox(height: 8),
              const Text('Para que todos trabajen con la misma versión, actualice antes de seguir. Lo guardado en el '
                  'celular no se pierde.', textAlign: TextAlign.center),
              if (notas.isNotEmpty) ...[
                const SizedBox(height: 12),
                TarjetaOdai(child: Text(notas)),
              ],
              const SizedBox(height: 16),
              if (motor.pendientes > 0)
                Text('${motor.pendientes} movimientos por enviar: se envían antes de actualizar.',
                    textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              if (_bajando) ...[
                LinearProgressIndicator(value: _avance),
                const SizedBox(height: 6),
                Text(_avance == null ? 'Preparando...' : 'Descargando ${(_avance! * 100).round()}%',
                    textAlign: TextAlign.center),
              ] else if (version != null)
                BotonGrande(icono: Icons.system_update, texto: 'Actualizar', onPressed: _actualizar)
              else
                const Text('La oficina aún no sube el archivo de la versión nueva. Sincronice más tarde.',
                    textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.sync),
                label: Text(motor.sincronizando ? 'Sincronizando...' : 'Sincronizar'),
                onPressed: motor.sincronizando || _bajando ? null : () => motor.sincronizar(),
              ),
              if (_mensaje != null)
                Padding(padding: const EdgeInsets.only(top: 12), child: Text(_mensaje!, textAlign: TextAlign.center)),
            ],
          ),
        );
      },
    );
  }
}
