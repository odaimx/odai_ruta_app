import 'package:flutter/material.dart';

import '../api.dart';
import '../motor.dart';
import '../tema.dart';
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

  ({String texto, String autor})? _frase;

  @override
  void initState() {
    super.initState();
    // Una frase distinta cada vez que se muestra la pantalla del PIN. Si aún no hay (la app recién instalada o
    // actualizada abre el PIN mientras sincroniza), se vuelve a buscar en cuanto termina la sincronización.
    widget.motor.addListener(_buscarFrase);
    _buscarFrase();
  }

  @override
  void dispose() {
    widget.motor.removeListener(_buscarFrase);
    super.dispose();
  }

  Future<void> _buscarFrase() async {
    if (_frase != null) return;
    final f = await widget.motor.fraseAlAzar();
    if (mounted && f != null && _frase == null) setState(() => _frase = f);
  }

  Widget _teclado(ThemeData tema) {
    Widget tecla(String t) {
      final Widget contenido = switch (t) {
        '<' => const Icon(Icons.backspace_outlined, size: 30, color: moradoOdai),
        'ok' => const Icon(Icons.check, size: 38, color: Colors.white),
        _ => Text(t, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w400, color: moradoOdai)),
      };
      return Expanded(
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: SizedBox(
            height: 58,
            child: t == 'ok'
                ? FilledButton(
                    key: const ValueKey('tecla_ok'),
                    onPressed: () => _tecla(t),
                    style: FilledButton.styleFrom(backgroundColor: moradoCabecera, padding: EdgeInsets.zero),
                    child: contenido)
                : OutlinedButton(
                    key: ValueKey('tecla_$t'),
                    onPressed: () => _tecla(t),
                    style: OutlinedButton.styleFrom(
                        backgroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        side: const BorderSide(color: bordeMorado, width: 1.5)),
                    child: contenido),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(children: [
        for (final fila in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
          ['<', '0', 'ok'],
        ])
          Row(children: [for (final t in fila) tecla(t)]),
      ]),
    );
  }

  Widget _fraseCelebre(ThemeData tema) {
    final f = _frase;
    if (f == null) return const SizedBox(height: 8);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('"${f.texto}"',
            key: const ValueKey('frase'),
            textAlign: TextAlign.center,
            style: tema.textTheme.titleMedium?.copyWith(fontStyle: FontStyle.italic, color: const Color(0xFF222222))),
        const SizedBox(height: 4),
        Text(f.autor,
            key: const ValueKey('frase_autor'),
            textAlign: TextAlign.right,
            style: tema.textTheme.bodyMedium?.copyWith(color: moradoOscuro, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final motor = widget.motor;
    final tema = Theme.of(context);
    return Scaffold(
      appBar: CabeceraOdai(
        titulo: motor.nombreVendedor.isEmpty ? 'Odai Ruta' : motor.nombreVendedor,
        subtitulo: motor.nombreEmpresa,
        derecha: IndicadorSenal(motor: motor, claro: true),
      ),
      bottomNavigationBar: const PieOdai(),
      body: LayoutBuilder(
        builder: (context, medidas) => SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: medidas.maxHeight),
            child: IntrinsicHeight(
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  Image.asset('assets/logo.png', height: 60),
                  const SizedBox(height: 6),
                  Text('Venta en Ruta', style: tema.textTheme.headlineSmall?.copyWith(color: const Color(0xFF222222))),
                  const SizedBox(height: 14),
                  _fraseCelebre(tema),
                  const Spacer(),
                  if (motor.bloqueoPin) ...[
                    const Icon(Icons.lock, size: 64, color: moradoOdai),
                    const SizedBox(height: 12),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text('Demasiados intentos. Conéctese a internet para desbloquear, o pida al supervisor '
                          'que le cambie el PIN.', textAlign: TextAlign.center),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: motor.sincronizando ? null : () => motor.sincronizar(),
                      icon: const Icon(Icons.sync),
                      label: Text(motor.sincronizando ? 'Conectando...' : 'Conectar'),
                    ),
                    if (motor.ultimoError != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(motor.ultimoError!, textAlign: TextAlign.center),
                      ),
                    const SizedBox(height: 24),
                  ] else ...[
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        6,
                        (i) => Container(
                          width: 26,
                          height: 26,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i < _pin.length ? moradoOdai : Colors.white,
                            border: Border.all(color: const Color(0xFF333333), width: 1.5),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text('Escribe tu PIN', style: tema.textTheme.titleMedium),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 8),
                      child: _validando
                          ? const LinearProgressIndicator(minHeight: 8)
                          : BarraAvance(valor: _pin.length / 6, alto: 8),
                    ),
                    SizedBox(
                      height: 22,
                      child: Text(_mensaje ?? '', textAlign: TextAlign.center, style: TextStyle(color: tema.colorScheme.error)),
                    ),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                      TextButton(onPressed: _solicitar, child: const Text('Olvidé mi PIN', style: TextStyle(fontSize: 16))),
                      TextButton(
                        onPressed: motor.sincronizando ? null : _conectar,
                        child: Text(motor.sincronizando ? 'Conectando...' : 'Ya me dieron PIN',
                            style: const TextStyle(fontSize: 16)),
                      ),
                    ]),
                    _teclado(tema),
                    const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
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
