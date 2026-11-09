# Odai Ruta (app Android para venta en ruta)

App Flutter del vendedor para trabajar **sin internet primero** contra Odoo 20 con `odai_ruta_movil` y
`odai_ruta_venta`. El contrato de la API está en `odai_ruta_venta/docs/api_movil.md`.

## Qué hace esta versión (base)

- **Emparejar con QR.** El supervisor crea el celular en Odoo (Venta en ruta › Celulares) y muestra el QR
  `{url, db, codigo}`. La app lo canjea por el token del dispositivo, que vive solo en el almacén seguro de Android.
- **Varias bases en el servidor.** Antes de llamar a la API abre `/web/login?db=<base>` y usa esa cookie; la
  identidad viene del token (`Authorization: Bearer`).
- **PIN** de 4 a 6 números, validado sin señal (PBKDF2-SHA256 con sal, igual que Odoo). 5 fallas bloquean hasta
  tener señal. Se vuelve a pedir tras 5 minutos fuera de la app.
- **Base local cifrada** (SQLCipher) con la llave en el almacén seguro: lo que bajó (jornadas, catálogo, precios,
  facturas, motivos) y la **cola** de lo que hace el vendedor.
- **Cola idempotente.** Todo se guarda primero en el celular con un uuid y sube en orden. `rechazado` (regla de
  negocio) queda a la vista del vendedor; una falla técnica se reintenta y tras 5 veces queda para la oficina.
- **Permiso para trabajar sin señal.** Cada conexión renueva `trabajar_hasta`; vencido, la app deja consultar pero
  no vender. Si el reloj del celular se atrasa para estirar el permiso, tampoco vende.
- **Comandos del supervisor:** bloquear, desbloquear, resincronizar y borrar (sube lo pendiente y borra base,
  token y llave).
- **Bajada incremental:** catálogo y precios solo bajan si cambiaron.

Siguiente: pantallas del vendedor (ruta, cliente, pedido, cobro, sin venta, cierre).

## Compilar

GitHub Actions (`.github/workflows/apk.yml`) revisa, prueba y compila el APK en cada cambio; se descarga desde la
pestaña Actions › la corrida › Artifacts. No hace falta instalar nada en la PC.

Para firmar como entrega, agregue los secretos `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
`ANDROID_KEY_ALIAS` y `ANDROID_KEY_PASSWORD`. Sin ellos se firma con la llave de depuración (solo para probar).

En local: `flutter pub get`, `flutter test`, `flutter build apk --release`. En modo depuración se permite
`http://`; el APK de entrega exige `https://`.
