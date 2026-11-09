import 'package:flutter_test/flutter_test.dart';
import 'package:odai_ruta/src/pin.dart';
import 'package:odai_ruta/src/version.dart';

void main() {
  test('PBKDF2 igual que hashlib.pbkdf2_hmac de Odoo', () {
    // python: hashlib.pbkdf2_hmac('sha256', b'4821', bytes.fromhex('00112233445566778899aabbccddeeff'), 1000).hex()
    const esperado = '5619120ab4097633a12f0cebc2817c743ed11fc69594f073b2ad47239f59c827';
    expect(pbkdf2Sha256Hex('4821', '00112233445566778899aabbccddeeff', 1000), esperado);
    const datos = DatosPin(sal: '00112233445566778899aabbccddeeff', hash: esperado, iteraciones: 1000);
    expect(verificarPinSincrono('4821', datos), isTrue);
    expect(verificarPinSincrono('4822', datos), isFalse);
  });

  test('versiones', () {
    expect(compararVersion('1.0.0', '1.0.1'), lessThan(0));
    expect(compararVersion('1.10.0', '1.9.9'), greaterThan(0));
    expect(compararVersion('1.0', '1.0.0'), 0);
  });
}
