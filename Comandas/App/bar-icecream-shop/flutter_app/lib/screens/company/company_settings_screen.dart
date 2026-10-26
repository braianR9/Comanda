import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../utils/api_response.dart';
import '../../providers/auth_provider.dart';
import '../purchases/purchase_api.dart';
import 'afip_certificate_section.dart';

class CompanySettingsScreen extends StatefulWidget {
  const CompanySettingsScreen({super.key});
  @override
  State<CompanySettingsScreen> createState() => _CompanySettingsScreenState();
}

class _CompanySettingsScreenState extends State<CompanySettingsScreen> {
  final _fields = <String, TextEditingController>{};
  final _form = GlobalKey<FormState>();
  bool _loading = true, _saving = false;
  String? _error, _image;
  int _version = 0, _concept = 1;
  String _environment = 'Homologacion';
  String _taxCondition = '';
  String _invoicingMode = 'Manual';
  static const _taxConditions = [
    'IVA Responsable Inscripto',
    'Responsable Monotributo',
    'IVA Sujeto Exento',
  ];
  late PurchaseApi _api;
  TextEditingController c(String key) =>
      _fields.putIfAbsent(key, TextEditingController.new);
  @override
  void initState() {
    super.initState();
    _api = PurchaseApi(context.read<AuthProvider>().session!.token);
    _load();
  }

  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final d = await _api.call('company-settings');
      if (!mounted) return;
      final company = d['company'] as Map<String, dynamic>;
      c('name').text = company['nombre'] ?? '';
      c('email').text = company['email'] ?? '';
      c('phone').text = company['telefono'] ?? '';
      c('address').text = d['address'] ?? '';
      c('website').text = d['website'] ?? '';
      final b = d['billing'] as Map<String, dynamic>;
      for (final k in [
        'legalName',
        'cuit',
        'fiscalAddress',
        'city',
        'province',
        'postalCode',
        'grossIncomeRegistration',
        'activityStart',
        'pointOfSale'
      ]) {
        c(k).text = b[k]?.toString() ?? '';
      }
      _version = d['version'];
      _environment = b['environment'] ?? 'Homologacion';
      _concept = b['concept'] ?? 1;
      _taxCondition = b['taxCondition'] ?? '';
      _invoicingMode = b['invoicingMode'] ?? 'Manual';
      _image = company['imagenUrl'];
      await context.read<AuthProvider>().updateCompany(company, _api.token);
    } catch (e) {
      if (mounted) _error = e.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final billing = <String, dynamic>{
        for (final k in [
          'legalName',
          'cuit',
          'fiscalAddress',
          'city',
          'province',
          'postalCode',
          'grossIncomeRegistration'
        ])
          k: c(k).text.trim(),
        'activityStart':
            c('activityStart').text.isEmpty ? null : c('activityStart').text,
        'pointOfSale': int.tryParse(c('pointOfSale').text),
        'taxCondition': _taxCondition,
        'environment': _environment,
        'concept': _concept,
        'invoicingMode': _invoicingMode
      };
      final d = await _api.call('company-settings', method: 'PUT', body: {
        for (final k in ['name', 'email', 'phone', 'address', 'website'])
          k: c(k).text.trim(),
        'billing': billing,
        'version': _version
      });
      if (!mounted) return;
      _version = d['version'];
      await context
          .read<AuthProvider>()
          .updateCompany(Map<String, dynamic>.from(d['company']), _api.token);
      if (mounted) _snack('Configuración guardada.');
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _upload() async {
    final auth = context.read<AuthProvider>();
    final session = auth.session!;
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty || !mounted) return;
    setState(() => _saving = true);
    try {
      final bytes = await files.first.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw Exception('La imagen no puede superar 5 MB.');
      }
      final request = http.MultipartRequest(
          'POST',
          Uri.parse(ApiConfig.baseUrl +
              ApiConfig.uploadImageEndpoint(session.idEmpresa)))
        ..headers.addAll({
          ApiConfig.apiKeyHeader: ApiConfig.apiKeyValue,
          'Authorization': 'Bearer ${_api.token}'
        })
        ..files.add(http.MultipartFile.fromBytes('Imagen', bytes,
            filename: files.first.name));
      final response = await request
          .send()
          .then(http.Response.fromStream)
          .timeout(ApiConfig.timeout);
      final d = decodeApiResponse(response);
      if (response.statusCode >= 400) {
        throw Exception(d['error'] ?? 'No se pudo subir la imagen.');
      }
      await auth.updateCompany(
          Map<String, dynamic>.from(d['data']), _api.token);
      if (mounted) setState(() => _image = d['data']['imagenUrl']);
    } catch (e) {
      if (mounted) _snack(e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Widget field(String key, String label,
          {bool required = false, int max = 200}) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: TextFormField(
              controller: c(key),
              maxLength: max,
              decoration: InputDecoration(labelText: label, counterText: ''),
              validator: (v) {
                if (required && (v ?? '').trim().isEmpty) {
                  return 'Completá este campo.';
                }
                if (key == 'pointOfSale' &&
                    v!.isNotEmpty &&
                    ((int.tryParse(v) ?? 0) < 1 ||
                        (int.tryParse(v) ?? 0) > 99999)) {
                  return 'Usá un número entre 1 y 99999.';
                }
                if (key == 'activityStart' &&
                    v!.isNotEmpty &&
                    (DateTime.tryParse(v) == null ||
                        !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v))) {
                  return 'Formato AAAA-MM-DD.';
                }
                return null;
              }));
  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(_error!),
        TextButton(onPressed: _load, child: const Text('Reintentar'))
      ]));
    }
    final url = _image == null
        ? null
        : (_image!.startsWith('http')
            ? _image!
            : '${ApiConfig.baseUrl}$_image');
    return DefaultTabController(
        length: 2,
        child: Scaffold(
            appBar: AppBar(
                title: const Text('Configuración de la empresa'),
                bottom: const TabBar(tabs: [
                  Tab(text: 'Datos de la empresa'),
                  Tab(text: 'Facturación')
                ])),
            body: AbsorbPointer(
                absorbing: _saving,
                child: Form(
                    key: _form,
                    child: Column(children: [
                      Expanded(
                          child: TabBarView(children: [
                        ListView(padding: const EdgeInsets.all(24), children: [
                          if (url != null)
                            Image.network(url,
                                height: 100,
                                errorBuilder: (_, __, ___) =>
                                    const Icon(Icons.business, size: 64)),
                          TextButton.icon(
                              onPressed: _upload,
                              icon: const Icon(Icons.add_photo_alternate),
                              label: const Text(
                                  'Cambiar foto · JPG, PNG o WebP (5 MB)')),
                          field('name', 'Nombre comercial',
                              required: true, max: 150),
                          field('phone', 'Teléfono', max: 50),
                          field('email', 'Email', max: 150),
                          field('address', 'Dirección', max: 300),
                          field('website', 'Sitio web'),
                        ]),
                        ListView(padding: const EdgeInsets.all(24), children: [
                          const Padding(
                              padding: EdgeInsets.only(bottom: 20),
                              child: Text(
                                  'Datos fiscales para la factura electrónica de ARCA (AFIP). Guardalos antes de generar el certificado.')),
                          field('legalName', 'Razón social'),
                          field('cuit', 'CUIT', max: 20),
                          DropdownButtonFormField<String>(
                              initialValue:
                                  _taxCondition.isEmpty ? null : _taxCondition,
                              decoration: const InputDecoration(
                                  labelText: 'Condición frente al IVA'),
                              items: [
                                for (final value in {
                                  ..._taxConditions,
                                  if (_taxCondition.isNotEmpty) _taxCondition
                                })
                                  DropdownMenuItem(
                                      value: value, child: Text(value))
                              ],
                              onChanged: (v) =>
                                  setState(() => _taxCondition = v!)),
                          const SizedBox(height: 16),
                          field('fiscalAddress', 'Domicilio fiscal', max: 300),
                          field('city', 'Localidad', max: 100),
                          field('province', 'Provincia', max: 100),
                          field('postalCode', 'Código postal', max: 15),
                          field('grossIncomeRegistration',
                              'Ingresos brutos / convenio multilateral',
                              max: 50),
                          field('activityStart',
                              'Inicio de actividades (AAAA-MM-DD)',
                              max: 10),
                          field('pointOfSale',
                              'Punto de venta electrónico (web services)',
                              max: 5),
                          DropdownButtonFormField<String>(
                              initialValue: _environment,
                              decoration: const InputDecoration(
                                  labelText: 'Ambiente de AFIP'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'Homologacion',
                                    child: Text('Homologación (pruebas)')),
                                DropdownMenuItem(
                                    value: 'Produccion',
                                    child: Text('Producción'))
                              ],
                              onChanged: (v) =>
                                  setState(() => _environment = v!)),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<int>(
                              initialValue: _concept,
                              decoration: const InputDecoration(
                                  labelText: 'Concepto habitual'),
                              items: const [
                                DropdownMenuItem(
                                    value: 1, child: Text('Productos')),
                                DropdownMenuItem(
                                    value: 2, child: Text('Servicios')),
                                DropdownMenuItem(
                                    value: 3,
                                    child: Text('Productos y servicios'))
                              ],
                              onChanged: (v) => setState(() => _concept = v!)),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                              initialValue: _invoicingMode,
                              decoration: const InputDecoration(
                                  labelText: 'Cuándo facturar'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'Manual',
                                    child: Text(
                                        'Al cobrar, preguntar si se factura')),
                                DropdownMenuItem(
                                    value: 'Automatico',
                                    child: Text(
                                        'Facturar automáticamente cada venta'))
                              ],
                              onChanged: (v) =>
                                  setState(() => _invoicingMode = v!)),
                          AfipCertificateSection(
                              api: _api, environment: _environment),
                        ]),
                      ])),
                      Padding(
                          padding: const EdgeInsets.all(16),
                          child: FilledButton(
                              onPressed: _saving ? null : _save,
                              child: Text(_saving
                                  ? 'Guardando…'
                                  : 'Guardar configuración'))),
                    ])))));
  }
}
