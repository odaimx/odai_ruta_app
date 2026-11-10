import 'package:flutter/material.dart';

import '../api.dart';
import '../motor.dart';
import '../ruta.dart';
import 'comun.dart';

final _rfcValido = RegExp(r'^[A-ZÑ&]{3,4}[0-9]{6}[A-Z0-9]{3}$');
const _rfcGenericos = ['XAXX010101000', 'XEXX010101000'];

/// Datos del cliente: alta nueva o corrección, con sus datos fiscales. Se guarda en el celular y sube al haber
/// señal. Las condiciones de venta (crédito, lista de precios, plazo) no se tocan aquí: son de la oficina.
class PantallaDatosCliente extends StatefulWidget {
  const PantallaDatosCliente({super.key, required this.motor, required this.jornadaId, this.visita});

  final Motor motor;
  final int jornadaId;

  /// La visita que se corrige; null para dar de alta un cliente nuevo.
  final Map? visita;

  @override
  State<PantallaDatosCliente> createState() => _PantallaDatosClienteState();
}

class _PantallaDatosClienteState extends State<PantallaDatosCliente> {
  static const _campos = [
    ('comercial', 'Nombre comercial', TextInputType.text),
    ('telefono', 'Teléfono', TextInputType.phone),
    ('correo', 'Correo', TextInputType.emailAddress),
    ('calle', 'Calle y número', TextInputType.streetAddress),
    ('colonia', 'Colonia', TextInputType.text),
    ('ciudad', 'Ciudad', TextInputType.text),
    ('cp', 'Código postal', TextInputType.number),
  ];

  /// Catálogos del SAT que se eligen de una lista (vienen de Odoo si está odai_cfdi).
  static const _catalogos = [
    ('regimen', 'Régimen fiscal'),
    ('uso', 'Uso del CFDI'),
    ('forma', 'Forma de pago'),
    ('metodo', 'Método de pago'),
  ];

  final _nombre = TextEditingController();
  final _rfc = TextEditingController();
  late final Map<String, TextEditingController> _control;
  final Map<String, int?> _elegido = {};
  int? _pais;
  int? _estado;

  Map _fiscalCatalogos = const {};
  Map _direccion = const {};
  bool _cargado = false;
  bool _guardando = false;

  bool get _nuevo => widget.visita == null;
  Map get _contactoActual => (widget.visita?['contacto'] as Map?) ?? const {};
  Map get _fiscalActual => (widget.visita?['fiscal'] as Map?) ?? const {};

  @override
  void initState() {
    super.initState();
    final v = widget.visita ?? const {};
    final c = _contactoActual;
    final f = _fiscalActual;
    // Si Odoo aún no manda "contacto", se toma lo que sí trae la visita.
    String actual(String clave) {
      final valor = c[clave];
      if (valor is String && valor.isNotEmpty) return valor;
      return switch (clave) {
        'comercial' => '${v['comercial'] ?? ''}',
        'telefono' => '${v['telefono'] ?? ''}',
        'correo' => '${f['correo'] ?? ''}',
        'cp' => '${f['cp'] ?? ''}',
        _ => '',
      };
    }

    _control = {for (final campo in _campos) campo.$1: TextEditingController(text: actual(campo.$1))};
    _rfc.text = '${f['rfc'] ?? ''}';
    if (_rfcGenericos.contains(_rfc.text)) _rfc.text = '';
    _nombre.text = '${c['nombre'] ?? v['cliente'] ?? ''}';
    // El nombre fiscal se ve mientras se escribe el RFC o el nombre.
    _rfc.addListener(_refrescar);
    _nombre.addListener(_refrescar);
    for (final cat in _catalogos) {
      final id = f[cat.$1];
      _elegido[cat.$1] = id is int ? id : null;
    }
    _pais = c['pais'] is int ? c['pais'] as int : null;
    _estado = c['estado'] is int ? c['estado'] as int : null;
    _cargarCatalogos();
  }

  Future<void> _cargarCatalogos() async {
    final config = (await Ruta.cargar(widget.motor)).config(widget.jornadaId);
    if (!mounted) return;
    setState(() {
      _fiscalCatalogos = (config['catalogos_fiscales'] as Map?) ?? const {};
      _direccion = (config['catalogos_direccion'] as Map?) ?? const {};
      _pais ??= _direccion['mexico'] is int ? _direccion['mexico'] as int : null;
      if (_nuevo && _elegido['metodo'] == null) {
        // De contado: pago en una sola exhibición.
        final pue = _lista('metodo').where((m) => m['clave'] == 'PUE' || '${m['name']}'.startsWith('PUE')).firstOrNull;
        _elegido['metodo'] = pue?['id'] as int?;
      }
      _cargado = true;
    });
  }

  void _refrescar() {
    if (mounted) setState(() {});
  }

  List<Map> _lista(String clave) => ((_fiscalCatalogos[clave] as List?) ?? const []).whereType<Map>().toList();

  bool get _esMexico => _pais != null && _pais == _direccion['mexico'];

  @override
  void dispose() {
    for (final c in [_nombre, _rfc, ..._control.values]) {
      c.dispose();
    }
    super.dispose();
  }

  String _digitos(String texto) {
    final d = texto.replaceAll(RegExp(r'\D'), '');
    return d.length > 10 ? d.substring(d.length - 10) : d;
  }

  Map<String, Object?> _fiscal() {
    final rfc = _rfc.text.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
    return {
      if (rfc.isNotEmpty) ...{
        'rfc': rfc,
        'razon_social': _nombre.text.trim().toUpperCase(),
        'cp': _control['cp']!.text.trim(),
        'correo': _control['correo']!.text.trim(),
      },
      for (final cat in _catalogos)
        if (_lista(cat.$1).isNotEmpty) cat.$1: _elegido[cat.$1] ?? false,
    };
  }

  Future<void> _guardar() async {
    final datos = <String, Object?>{for (final e in _control.entries) e.key: e.value.text.trim()};
    datos['nombre'] = _nombre.text.trim();
    if (_pais != null) datos['pais'] = _pais;
    datos['estado'] = _esMexico ? (_estado ?? false) : false;
    final cp = datos['cp'] as String;
    final correo = datos['correo'] as String;
    if (_nombre.text.trim().length < 3) {
      avisar(context, 'Escriba el nombre del cliente.', error: true);
      return;
    }
    if (cp.isNotEmpty && !RegExp(r'^\d{5}$').hasMatch(cp)) {
      avisar(context, 'El código postal lleva 5 dígitos.', error: true);
      return;
    }
    if (correo.isNotEmpty && !correo.contains('@')) {
      avisar(context, 'El correo no es válido.', error: true);
      return;
    }
    final fiscal = _fiscal();
    final rfc = fiscal['rfc'] as String?;
    if (rfc != null) {
      if (!_rfcValido.hasMatch(rfc) || _rfcGenericos.contains(rfc)) {
        avisar(context, 'El RFC no es válido: 12 caracteres (empresa) o 13 (persona física).', error: true);
        return;
      }
      if (cp.isEmpty) {
        avisar(context, 'Para facturar hace falta el código postal.', error: true);
        return;
      }
    }
    final ruta = await Ruta.cargar(widget.motor);
    if (!mounted) return;
    final telefono = datos['telefono'] as String;
    if (_nuevo && _digitos(telefono).length == 10) {
      final mismo =
          ruta.visitas(widget.jornadaId).where((v) => _digitos('${v['telefono'] ?? ''}') == _digitos(telefono)).firstOrNull;
      if (mismo != null) {
        final seguir = await confirmar(context, 'Cliente repetido',
            '${mismo['cliente']} ya tiene ese teléfono en su ruta. ¿Dar de alta otro cliente de todos modos?',
            si: 'Dar de alta');
        if (!seguir || !mounted) return;
      }
    }
    setState(() => _guardando = true);
    try {
      if (_nuevo) {
        final uuid = await widget.motor.registrar('cliente_nuevo', {
          'jornada_id': widget.jornadaId,
          ...datos,
          'fiscal': fiscal,
        });
        if (mounted) {
          avisar(context, 'Cliente dado de alta. Se vende de contado; la oficina lo revisa.');
          Navigator.pop(context, Ruta.idProvisional(uuid));
        }
      } else {
        String igual(Object? v) => v == null || v == false ? '' : '$v';
        final antes = _contactoActual;
        final cambios = {
          for (final e in datos.entries)
            if (igual(antes[e.key]) != igual(e.value)) e.key: e.value,
        };
        final fiscalAntes = _fiscalActual;
        final fiscalCambio = fiscal.entries
            .any((e) => igual(fiscalAntes[e.key]).toUpperCase() != igual(e.value).toUpperCase());
        if (cambios.isNotEmpty || fiscalCambio) {
          await widget.motor.registrar('cliente', {
            'visita_id': widget.visita!['id'],
            'contacto': cambios,
            if (fiscalCambio) 'fiscal': fiscal,
          });
        }
        if (mounted) {
          avisar(context, cambios.isEmpty && !fiscalCambio ? 'Sin cambios.' : 'Datos guardados.');
          Navigator.pop(context);
        }
      }
    } on ApiError catch (e) {
      if (mounted) avisar(context, e.mensaje, error: true);
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Widget _campoTexto(TextEditingController control, String etiqueta,
          {TextInputType? teclado, TextCapitalization mayusculas = TextCapitalization.none}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: control,
          keyboardType: teclado,
          textCapitalization: mayusculas,
          decoration: InputDecoration(labelText: etiqueta),
        ),
      );

  Widget _desplegable(String etiqueta, List<Map> opciones, int? valor, ValueChanged<int?> cambio) {
    final ids = opciones.map((o) => o['id']).toSet();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DropdownButtonFormField<int?>(
        initialValue: ids.contains(valor) ? valor : null,
        isExpanded: true,
        decoration: InputDecoration(labelText: etiqueta),
        items: [
          const DropdownMenuItem<int?>(value: null, child: Text('Sin elegir')),
          for (final o in opciones)
            DropdownMenuItem<int?>(
                value: o['id'] as int, child: Text('${o['name']}', overflow: TextOverflow.ellipsis)),
        ],
        onChanged: cambio,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tema = Theme.of(context);
    final paises = ((_direccion['paises'] as List?) ?? const []).whereType<Map>().toList();
    final estados = ((_direccion['estados'] as List?) ?? const []).whereType<Map>().where((e) => e['pais'] == _pais).toList();
    final hayFiscales = _catalogos.any((c) => _lista(c.$1).isNotEmpty);
    return Scaffold(
      appBar: AppBar(title: Text(_nuevo ? 'Cliente nuevo' : 'Datos del cliente')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_nuevo) ...[
            Card(
              color: tema.colorScheme.secondaryContainer,
              child: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('El cliente nuevo compra de contado y con la lista de precios general. La oficina le '
                    'asigna crédito u otra lista después de revisarlo.'),
              ),
            ),
            const SizedBox(height: 8),
          ],
          _campoTexto(_nombre, 'Nombre (si se factura, igual a la Constancia) *', mayusculas: TextCapitalization.words),
          for (final c in _campos) _campoTexto(_control[c.$1]!, c.$2, teclado: c.$3),
          if (_esMexico && estados.isNotEmpty)
            _desplegable('Estado', estados, _estado, (v) => setState(() => _estado = v)),
          if (paises.isNotEmpty)
            _desplegable('País', paises, _pais, (v) => setState(() {
                  _pais = v;
                  _estado = null;
                })),
          const SizedBox(height: 4),
          Text('Datos fiscales', style: tema.textTheme.titleMedium),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 10),
            child: Text('Solo si el cliente pide factura. Sin RFC se le vende igual.', style: tema.textTheme.bodySmall),
          ),
          _campoTexto(_rfc, 'RFC', mayusculas: TextCapitalization.characters),
          if (_rfc.text.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Nombre fiscal (se toma del nombre)', enabled: false),
                child: Text(_nombre.text.trim().toUpperCase(), style: const TextStyle(color: Color(0xFF111111))),
              ),
            ),
          if (hayFiscales)
            for (final cat in _catalogos)
              if (_lista(cat.$1).isNotEmpty)
                _desplegable(cat.$2, _lista(cat.$1), _elegido[cat.$1], (v) => setState(() => _elegido[cat.$1] = v)),
          if (_cargado && !hayFiscales)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text('Régimen, uso del CFDI y formas de pago aparecen al sincronizar.', style: tema.textTheme.bodySmall),
            ),
          if (!_nuevo)
            Text('Crédito, lista de precios y plazo de pago los cambia la oficina.', style: tema.textTheme.bodySmall),
          const SizedBox(height: 8),
          BotonGrande(
            icono: Icons.save,
            texto: _guardando ? 'Guardando...' : (_nuevo ? 'Dar de alta' : 'Guardar'),
            onPressed: _guardando ? null : _guardar,
          ),
          Text('Funciona sin señal: se envía a Odoo en cuanto haya conexión.', style: tema.textTheme.bodySmall),
        ],
      ),
    );
  }
}
