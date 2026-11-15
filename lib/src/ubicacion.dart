import 'dart:async';
import 'dart:math' as math;

import 'package:geolocator/geolocator.dart';

/// Una posición del celular.
class Posicion {
  const Posicion(this.lat, this.lon, {this.precision = 0, this.velocidad = 0, DateTime? momento}) : _momento = momento;

  final double lat;
  final double lon;
  final double precision;
  final double velocidad;
  final DateTime? _momento;

  DateTime get momento => _momento ?? DateTime.now();

  Map<String, Object?> paraOdoo() => {
    'lat': lat,
    'lon': lon,
    'precision': precision,
    'velocidad': velocidad,
    'momento': momento.toUtc().toIso8601String(),
  };
}

/// Distancia en metros (haversine).
double distanciaM(double lat1, double lon1, double lat2, double lon2) {
  const r = 6371000.0;
  double rad(double g) => g * math.pi / 180;
  final dp = rad(lat2 - lat1), dl = rad(lon2 - lon1);
  final a = math.pow(math.sin(dp / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dl / 2), 2);
  return 2 * r * math.asin(math.min(1.0, math.sqrt(a)));
}

/// De dónde sale la ubicación. En las pruebas se cambia por una fija.
abstract class Ubicador {
  /// La posición actual, o null si el vendedor negó el permiso, no hay GPS o tarda demasiado. Nunca lanza.
  Future<Posicion?> actual();
}

class UbicadorGps implements Ubicador {
  Posicion? _ultima;

  Future<bool> _permiso() async {
    if (!await Geolocator.isLocationServiceEnabled()) return false;
    var permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) permiso = await Geolocator.requestPermission();
    return permiso == LocationPermission.whileInUse || permiso == LocationPermission.always;
  }

  @override
  Future<Posicion?> actual() async {
    try {
      if (!await _permiso()) return null;
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, timeLimit: Duration(seconds: 12)),
      );
      return _ultima = Posicion(
        p.latitude,
        p.longitude,
        precision: p.accuracy,
        velocidad: p.speed < 0 ? 0 : p.speed,
        momento: DateTime.now(),
      );
    } catch (_) {
      // Sin fijación a tiempo: la última conocida si es reciente (menos de 5 minutos).
      final u = _ultima;
      if (u != null && DateTime.now().difference(u.momento) < const Duration(minutes: 5)) return u;
      try {
        final p = await Geolocator.getLastKnownPosition();
        if (p == null || DateTime.now().difference(p.timestamp) > const Duration(minutes: 5)) return null;
        return Posicion(p.latitude, p.longitude, precision: p.accuracy, momento: p.timestamp);
      } catch (_) {
        return null;
      }
    }
  }
}
