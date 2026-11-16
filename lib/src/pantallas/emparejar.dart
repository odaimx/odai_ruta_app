import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../almacen.dart';
import '../api.dart';
import '../motor.dart';
import 'comun.dart';

/// Primer uso: el vendedor escanea el QR que el supervisor muestra en Odoo (Venta en ruta › Configuración › Celulares).
class PantallaEmparejar extends StatefulWidget {
  const PantallaEmparejar({super.key, required this.motor});

  final Motor motor;

  @override
  State<PantallaEmparejar> createState() => _PantallaEmparejarState();
}

class _PantallaEmparejarState extends State<PantallaEmparejar> {
  final _camara = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _trabajando = false;
  bool _escaneando = false;
  String? _error;

  @override
  void dispose() {
    _camara.dispose();
    super.dispose();
  }

  Future<void> _usar(String texto) async {
    if (_trabajando) return;
    setState(() {
      _trabajando = true;
      _error = null;
    });
    try {
      await widget.motor.emparejar(texto);
    } on ApiError catch (e) {
      _error = e.mensaje;
    } on SinSenal {
      _error = 'Sin señal. Para emparejar el celular se necesita internet.';
    } catch (e) {
      _error = 'No se pudo emparejar: $e';
    }
    if (mounted) {
      setState(() {
        _trabajando = false;
        _escaneando = _error == null ? false : _escaneando;
      });
    }
  }

  /// Sin QR (lejos de la oficina): el mensaje que mandó el supervisor por WhatsApp o Telegram, o el código que
  /// dictó por teléfono, con el servidor y la base (se recuerdan del celular si ya estuvo conectado).
  Future<void> _sinQr() async {
    final almacen = widget.motor.almacen;
    final servidor = TextEditingController(text: await almacen.leer(Claves.url) ?? 'https://');
    final base = TextEditingController(text: await almacen.leer(Claves.db) ?? '');
    final codigo = TextEditingController();
    if (!mounted) return;
    Future<void> pegar(StateSetter refrescar) async {
      final texto = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
      final datos = DatosQr.delMensaje(texto);
      if (datos == null) {
        if (mounted) avisar(context, 'No se encontró un mensaje de activación copiado.', error: true);
        return;
      }
      refrescar(() {
        servidor.text = datos['url']!;
        base.text = datos['db']!;
        codigo.text = datos['codigo']!;
      });
    }

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, refrescar) => Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.of(c).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Activar sin QR', style: Theme.of(c).textTheme.titleLarge),
              const SizedBox(height: 6),
              const Text('Copie el mensaje que le mandó su supervisor y toque "Pegar mensaje", o escriba el código que '
                  'le dicte. Sirve una sola vez y vence en 15 minutos.'),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                key: const ValueKey('pegar_mensaje'),
                onPressed: () => pegar(refrescar),
                icon: const Icon(Icons.content_paste),
                label: const Text('Pegar mensaje'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: servidor,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(labelText: 'Servidor'),
              ),
              TextField(controller: base, decoration: const InputDecoration(labelText: 'Base de datos')),
              TextField(
                key: const ValueKey('codigo_manual'),
                controller: codigo,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(labelText: 'Código', hintText: 'XXXX-XXXX-XXXX'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const ValueKey('activar_manual'),
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                child: const Text('Activar'),
              ),
            ],
          ),
        ),
      ),
    );
    final texto = jsonEncode({'url': servidor.text.trim(), 'db': base.text.trim(), 'codigo': codigo.text.trim()});
    servidor.dispose();
    base.dispose();
    codigo.dispose();
    if (ok == true) await _usar(texto);
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: const CabeceraOdai(titulo: 'Odai Ruta'),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(child: Image.asset('assets/logo.png', height: 48)),
              const SizedBox(height: 16),
              Text('Conectar este celular', style: tema.textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text('Pida a su supervisor el código QR del celular (en Odoo: Venta en ruta › Configuración › Celulares) '
                  'y escanéelo. Si está lejos, él puede mandarle el código por WhatsApp o dictárselo. Sirve una sola '
                  'vez y vence en 15 minutos.'),
              const SizedBox(height: 16),
              if (_error != null)
                Card(
                  color: tema.colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(_error!, style: TextStyle(color: tema.colorScheme.onErrorContainer)),
                  ),
                ),
              Expanded(
                child: _escaneando
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: MobileScanner(
                          controller: _camara,
                          onDetect: (captura) {
                            final valor = captura.barcodes.firstOrNull?.rawValue;
                            if (valor != null) _usar(valor);
                          },
                        ),
                      )
                    : const Center(child: Icon(Icons.qr_code_2, size: 160)),
              ),
              const SizedBox(height: 16),
              if (_trabajando)
                const Center(child: CircularProgressIndicator())
              else
              ...[
                FilledButton.icon(
                  onPressed: () => setState(() => _escaneando = !_escaneando),
                  icon: Icon(_escaneando ? Icons.close : Icons.qr_code_scanner),
                  label: Text(_escaneando ? 'Cancelar' : 'Escanear código'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('sin_qr'),
                  onPressed: _sinQr,
                  icon: const Icon(Icons.sms_outlined),
                  label: const Text('Activar sin QR (WhatsApp o código)'),
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
