import 'package:flutter_test/flutter_test.dart';
import 'package:odai_ruta/src/pantallas/comun.dart';

void main() {
  test('montos sugeridos para cobrar rápido', () {
    expect(montosSugeridos(145), [150, 200, 500, 1000]);
    expect(montosSugeridos(182.5), [200, 500, 1000]);
    expect(montosSugeridos(225), [250, 300, 400, 500]);
    expect(montosSugeridos(0), isEmpty);
  });
}
