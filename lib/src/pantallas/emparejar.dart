import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../api.dart';
import '../motor.dart';

/// Primer uso: el vendedor escanea el QR que el supervisor muestra en Odoo (Venta en ruta › Celulares).
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

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Odai Ruta')),
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
              const Text('Pida a su supervisor el código QR del celular (en Odoo: Venta en ruta › Celulares) '
                  'y escanéelo. El código sirve una sola vez y vence en 15 minutos.'),
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
                FilledButton.icon(
                  onPressed: () => setState(() => _escaneando = !_escaneando),
                  icon: Icon(_escaneando ? Icons.close : Icons.qr_code_scanner),
                  label: Text(_escaneando ? 'Cancelar' : 'Escanear código'),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
