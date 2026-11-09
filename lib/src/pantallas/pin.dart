import 'package:flutter/material.dart';

import '../motor.dart';

/// El vendedor abre la app con su PIN, también sin señal.
class PantallaPin extends StatefulWidget {
  const PantallaPin({super.key, required this.motor});

  final Motor motor;

  @override
  State<PantallaPin> createState() => _PantallaPinState();
}

class _PantallaPinState extends State<PantallaPin> {
  String _pin = '';
  bool _validando = false;
  String? _mensaje;

  Future<void> _tecla(String tecla) async {
    if (_validando) return;
    if (tecla == '<') {
      setState(() => _pin = _pin.isEmpty ? '' : _pin.substring(0, _pin.length - 1));
      return;
    }
    if (tecla == 'ok') {
      if (_pin.length < 4) return;
      setState(() => _validando = true);
      final ok = await widget.motor.desbloquear(_pin);
      if (!mounted) return;
      setState(() {
        _validando = false;
        _pin = '';
        if (!ok) {
          final quedan = maxIntentosPin - widget.motor.intentosPin;
          _mensaje = widget.motor.bloqueoPin
              ? null
              : 'PIN incorrecto. ${quedan == 1 ? 'Queda 1 intento' : 'Quedan $quedan intentos'}.';
        }
      });
      return;
    }
    if (_pin.length < 6) setState(() => _pin += tecla);
  }

  @override
  Widget build(BuildContext context) {
    final motor = widget.motor;
    final tema = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const SizedBox(height: 24),
              Text(motor.nombreVendedor, style: tema.textTheme.titleLarge),
              Text(motor.nombreEmpresa, style: tema.textTheme.bodyMedium),
              const SizedBox(height: 24),
              if (motor.bloqueoPin) ...[
                const Icon(Icons.lock, size: 64),
                const SizedBox(height: 12),
                const Text('Demasiados intentos. Conéctese a internet para desbloquear, o pida al supervisor '
                    'que le cambie el PIN.', textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: motor.sincronizando ? null : () => motor.sincronizar(),
                  icon: const Icon(Icons.sync),
                  label: Text(motor.sincronizando ? 'Conectando...' : 'Conectar'),
                ),
                if (motor.ultimoError != null) Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(motor.ultimoError!, textAlign: TextAlign.center),
                ),
              ] else ...[
                Text('Escriba su PIN', style: tema.textTheme.titleMedium),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    6,
                    (i) => Padding(
                      padding: const EdgeInsets.all(6),
                      child: Icon(i < _pin.length ? Icons.circle : Icons.circle_outlined, size: 18),
                    ),
                  ),
                ),
                SizedBox(height: 24, child: _validando ? const LinearProgressIndicator() : Text(_mensaje ?? '')),
                const Spacer(),
                for (final fila in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['<', '0', 'ok'],
                ])
                  Row(
                    children: [
                      for (final tecla in fila)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(6),
                            child: SizedBox(
                              height: 64,
                              child: tecla == 'ok'
                                  ? FilledButton(onPressed: () => _tecla(tecla), child: const Icon(Icons.check))
                                  : OutlinedButton(
                                      onPressed: () => _tecla(tecla),
                                      child: tecla == '<'
                                          ? const Icon(Icons.backspace_outlined)
                                          : Text(tecla, style: tema.textTheme.headlineSmall),
                                    ),
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
