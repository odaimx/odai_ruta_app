import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/almacen.dart';
import 'src/base_local.dart';
import 'src/motor.dart';
import 'src/pantallas/emparejar.dart';
import 'src/pantallas/inicio.dart';
import 'src/pantallas/pin.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final motor = Motor(
    almacen: AlmacenSeguro(),
    abrirBase: BaseLocal.abrir,
    borrarBase: BaseLocal.borrarArchivo,
    // http:// solo al programar; el APK de entrega exige https://.
    permitirHttp: kDebugMode,
  );
  runApp(OdaiRutaApp(motor: motor));
  motor.iniciar().then((_) => motor.sincronizar());
}

class OdaiRutaApp extends StatefulWidget {
  const OdaiRutaApp({super.key, required this.motor});

  final Motor motor;

  @override
  State<OdaiRutaApp> createState() => _OdaiRutaAppState();
}

class _OdaiRutaAppState extends State<OdaiRutaApp> with WidgetsBindingObserver {
  DateTime? _enSegundoPlano;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _enSegundoPlano = DateTime.now();
    } else if (state == AppLifecycleState.resumed) {
      // Más de 5 minutos fuera de la app: se vuelve a pedir el PIN.
      final desde = _enSegundoPlano;
      if (desde != null && DateTime.now().difference(desde) > const Duration(minutes: 5)) {
        widget.motor.bloquearPantalla();
      }
      widget.motor.sincronizar();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Odai Ruta',
      debugShowCheckedModeBanner: false,
      theme: temaOdai(Brightness.light),
      darkTheme: temaOdai(Brightness.dark),
      home: ListenableBuilder(
        listenable: widget.motor,
        builder: (context, _) {
          final motor = widget.motor;
          if (!motor.listo) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          if (!motor.emparejado) return PantallaEmparejar(motor: motor);
          if (!motor.desbloqueado) return PantallaPin(motor: motor);
          if (motor.pinTemporal) return PantallaNuevoPin(motor: motor, obligatorio: true);
          return PantallaInicio(motor: motor);
        },
      ),
    );
  }
}

/// Colores de Odai: azul marino de base, el morado del logo como acento y su azul claro como tercer color.
const azulMarino = Color(0xFF1B2A4A);
const moradoOdai = Color(0xFF8A64DE);
const azulOdai = Color(0xFF54AAF6);

ThemeData temaOdai(Brightness brillo) {
  final oscuro = brillo == Brightness.dark;
  final colores = ColorScheme.fromSeed(
    seedColor: azulMarino,
    brightness: brillo,
    primary: oscuro ? const Color(0xFF9DB4E0) : azulMarino,
    secondary: moradoOdai,
    tertiary: azulOdai,
  );
  return ThemeData(
    colorScheme: colores,
    useMaterial3: true,
    appBarTheme: const AppBarTheme(backgroundColor: azulMarino, foregroundColor: Colors.white),
    cardTheme: CardThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
  );
}
