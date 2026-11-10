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
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1F6FB2), useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF1F6FB2), useMaterial3: true, brightness: Brightness.dark),
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
