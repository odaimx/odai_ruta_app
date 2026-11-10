/// Versión de la app que se reporta al servidor. Debe coincidir con `version` de pubspec.yaml.
const String appVersion = '1.0.1';

/// Número de compilación que pone el CI (--dart-define=COMPILACION=...).
const String compilacion = String.fromEnvironment('COMPILACION', defaultValue: 'local');

/// Versión con compilación, para mostrarla en pantalla.
const String appVersionCompleta = '$appVersion ($compilacion)';

/// Compara versiones "1.2.3". Negativo si [a] < [b], cero si son iguales, positivo si [a] > [b].
int compararVersion(String a, String b) {
  List<int> partes(String v) =>
      v.split('+').first.split('.').map((p) => int.tryParse(p.trim()) ?? 0).toList();
  final pa = partes(a), pb = partes(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0, y = i < pb.length ? pb[i] : 0;
    if (x != y) return x - y;
  }
  return 0;
}
