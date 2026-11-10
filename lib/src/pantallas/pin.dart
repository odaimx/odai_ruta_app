import 'package:flutter/material.dart';

import '../api.dart';
import '../motor.dart';
import 'comun.dart';

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

  Future<void> _solicitar() async {
    final seguir = await confirmar(context, 'Olvidé mi PIN',
        'Se avisará a su supervisor para que le dé un PIN temporal. Con él entra y pone uno nuevo. ¿Pedirlo?',
        si: 'Pedir');
    if (!seguir || !mounted) return;
    try {
      final mensaje = await widget.motor.solicitarPin();
      if (mounted) setState(() => _mensaje = mensaje);
    } on ApiError catch (e) {
      if (mounted) setState(() => _mensaje = e.mensaje);
    }
  }

  /// Baja el PIN temporal que puso el supervisor.
  Future<void> _conectar() async {
    await widget.motor.sincronizar();
    if (!mounted) return;
    setState(() => _mensaje = widget.motor.ultimoError ??
        (widget.motor.pinTemporal ? 'Ya llegó su PIN temporal. Escríbalo.' : 'Conectado. Aún no hay PIN nuevo.'));
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
              const SizedBox(height: 16),
              Image.asset('assets/logo.png', height: 44),
              const SizedBox(height: 16),
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
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  TextButton(onPressed: _solicitar, child: const Text('Olvidé mi PIN')),
                  TextButton(
                    onPressed: motor.sincronizando ? null : _conectar,
                    child: Text(motor.sincronizando ? 'Conectando...' : 'Ya me dieron PIN'),
                  ),
                ]),
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


/// El vendedor pone su propio PIN. Obligatorio al entrar con el PIN temporal que le dio el supervisor.
class PantallaNuevoPin extends StatefulWidget {
  const PantallaNuevoPin({super.key, required this.motor, this.obligatorio = false});

  final Motor motor;
  final bool obligatorio;

  @override
  State<PantallaNuevoPin> createState() => _PantallaNuevoPinState();
}

class _PantallaNuevoPinState extends State<PantallaNuevoPin> {
  final _pin = TextEditingController();
  final _otraVez = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _otraVez.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    final pin = _pin.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      setState(() => _error = 'El PIN debe tener de 4 a 6 números.');
      return;
    }
    if (pin != _otraVez.text.trim()) {
      setState(() => _error = 'Los dos PIN no son iguales.');
      return;
    }
    if (RegExp(r'^(\d)\1+$').hasMatch(pin) || '0123456789'.contains(pin) || '9876543210'.contains(pin)) {
      setState(() => _error = 'Ese PIN es muy fácil de adivinar. Elija otro.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.motor.cambiarPin(pin);
      if (!mounted) return;
      avisar(context, 'Listo. Desde ahora entre con su PIN nuevo.');
      if (!widget.obligatorio) Navigator.pop(context);
    } on ApiError catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    InputDecoration campo(String texto) => InputDecoration(labelText: texto, border: const OutlineInputBorder());
    return Scaffold(
      appBar: AppBar(title: const Text('Su PIN'), automaticallyImplyLeading: !widget.obligatorio),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            widget.obligatorio
                ? 'Entró con un PIN temporal. Ponga ahora su propio PIN: solo usted lo sabrá, ni el supervisor lo ve.'
                : 'Ponga un PIN nuevo. Solo usted lo sabrá.',
            style: tema.textTheme.bodyLarge,
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pin,
            obscureText: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            decoration: campo('PIN nuevo (4 a 6 números)'),
          ),
          TextField(
            controller: _otraVez,
            obscureText: true,
            maxLength: 6,
            keyboardType: TextInputType.number,
            decoration: campo('Escríbalo otra vez'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: tema.colorScheme.error)),
            ),
          BotonGrande(icono: Icons.lock_reset, texto: _guardando ? 'Guardando...' : 'Guardar PIN', onPressed: _guardando ? null : _guardar),
          if (widget.obligatorio) ...[
            const SizedBox(height: 8),
            TextButton(onPressed: widget.motor.bloquearPantalla, child: const Text('Salir')),
          ],
        ],
      ),
    );
  }
}
