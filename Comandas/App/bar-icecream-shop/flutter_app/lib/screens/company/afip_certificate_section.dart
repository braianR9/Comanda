import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../purchases/purchase_api.dart';

/// Certificado digital de AFIP de un ambiente: pedido (CSR), carga y prueba.
class AfipCertificateSection extends StatefulWidget {
  final PurchaseApi api;
  final String environment;

  /// Ambiente elegido en la configuración (el que se usa para facturar).
  final String activeEnvironment;
  const AfipCertificateSection(
      {super.key,
      required this.api,
      required this.environment,
      required this.activeEnvironment});
  @override
  State<AfipCertificateSection> createState() => _AfipCertificateSectionState();
}

class _AfipCertificateSectionState extends State<AfipCertificateSection> {
  Map<String, dynamic>? _status;
  final _alias = TextEditingController(text: 'comandas');
  final _certificate = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _messageIsError = false;

  bool get _production => widget.environment == 'Produccion';
  Map<String, dynamic>? get _current => _status == null
      ? null
      : Map<String, dynamic>.from(
          _status![_production ? 'produccion' : 'homologacion'] as Map);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _alias.dispose();
    _certificate.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await action();
    } catch (e) {
      _show(e.toString().replaceFirst('Exception: ', ''), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _show(String text, {bool error = false}) {
    if (mounted) {
      setState(() {
        _message = text;
        _messageIsError = error;
      });
    }
  }

  Future<void> _load() => _run(() async {
        final data = await widget.api.call('afip/certificado');
        if (mounted) setState(() => _status = Map<String, dynamic>.from(data));
      });

  Future<void> _createRequest() async {
    if (_current?['hasCertificate'] == true) {
      final ok = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
                title: const Text('¿Generar un certificado nuevo?'),
                content: const Text(
                    'El certificado actual deja de usarse en este sistema hasta que cargues el nuevo que te entregue ARCA.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Generar')),
                ],
              ));
      if (ok != true) return;
    }
    await _run(() async {
      await widget.api.call('afip/certificado/csr', method: 'POST', body: {
        'environment': widget.environment,
        'alias': _alias.text.trim(),
      });
      final data = await widget.api.call('afip/certificado');
      if (mounted) setState(() => _status = Map<String, dynamic>.from(data));
      _show('Pedido generado. Copialo y subilo en ARCA.');
    });
  }

  Future<void> _upload() => _run(() async {
        if (_certificate.text.trim().isEmpty) {
          throw Exception('Pegá el certificado que te entregó ARCA.');
        }
        final data =
            await widget.api.call('afip/certificado', method: 'PUT', body: {
          'environment': widget.environment,
          'certificate': _certificate.text.trim(),
        });
        _certificate.clear();
        if (mounted) setState(() => _status = Map<String, dynamic>.from(data));
        _show('Certificado cargado. Probá la conexión.');
      });

  Future<void> _test() => _run(() async {
        final data = Map<String, dynamic>.from(
            await widget.api.call(
                'afip/probar?environment=${widget.environment}',
                method: 'POST'));
        _show('${data['message']}\n${data['servers']}');
      });

  @override
  Widget build(BuildContext context) {
    final current = _current;
    final hasCertificate = current?['hasCertificate'] == true;
    final csr = current?['csr'] as String?;
    final expires =
        DateTime.tryParse(current?['expiresAt']?.toString() ?? '')?.toLocal();
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 24),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                    'Certificado de ARCA · ${_production ? 'Producción (facturas reales)' : 'Homologación (pruebas)'}',
                    style: theme.textTheme.titleMedium),
                if (widget.environment == widget.activeEnvironment)
                  const Chip(
                      label: Text('En uso'),
                      visualDensity: VisualDensity.compact),
              ]),
          const SizedBox(height: 8),
          if (_status == null && _busy) const LinearProgressIndicator(),
          if (_status?['encryptionConfigured'] == false)
            Text(
                'Falta configurar Afip:CredentialKey en el servidor. Pedíselo a quien instaló el sistema.',
                style: TextStyle(color: theme.colorScheme.error)),
          if (hasCertificate)
            Text(
                'Certificado cargado${expires == null ? '' : ', vence el ${expires.day}/${expires.month}/${expires.year}'}${current?['expired'] == true ? ' (VENCIDO)' : ''}.\n${current?['subject'] ?? ''}')
          else
            Text(_production
                ? '1. Generá el pedido. 2. En ARCA, entrá a "Administración de Certificados Digitales", agregá un alias, subí el pedido y descargá el certificado. 3. En "Administrador de Relaciones de Clave Fiscal", autorizá ese alias al servicio "Facturación electrónica" (wsfe). 4. Pegá el certificado acá.'
                : '1. Generá el pedido. 2. En ARCA, entrá a "WSASS - Autogestión Certificados Homologación", creá un certificado nuevo pegando el pedido y copiá el resultado. 3. En WSASS, creá la autorización del alias al servicio "wsfe". 4. Pegá el certificado acá.'),
          const SizedBox(height: 16),
          Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                    width: 200,
                    child: TextField(
                        controller: _alias,
                        decoration:
                            const InputDecoration(labelText: 'Alias en ARCA'))),
                OutlinedButton.icon(
                    onPressed: _busy ? null : _createRequest,
                    icon: const Icon(Icons.key),
                    label: Text(hasCertificate
                        ? 'Generar certificado nuevo'
                        : 'Generar pedido (CSR)')),
                if (hasCertificate)
                  FilledButton.icon(
                      onPressed: _busy ? null : _test,
                      icon: const Icon(Icons.wifi_tethering),
                      label: const Text('Probar conexión con ARCA')),
              ]),
          if (csr != null) ...[
            const SizedBox(height: 16),
            Row(children: [
              const Expanded(
                  child:
                      Text('Pedido de certificado (CSR) para subir a ARCA:')),
              TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: csr));
                    _show('Pedido copiado al portapapeles.');
                  },
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar')),
            ]),
            Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                color: const Color(0xFFF1E9DC),
                child: SelectableText(csr,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 11))),
            const SizedBox(height: 16),
            TextField(
                controller: _certificate,
                minLines: 4,
                maxLines: 8,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                decoration: const InputDecoration(
                    labelText:
                        'Certificado que entregó ARCA (-----BEGIN CERTIFICATE-----…)',
                    border: OutlineInputBorder())),
            const SizedBox(height: 8),
            FilledButton(
                onPressed: _busy ? null : _upload,
                child: const Text('Cargar certificado')),
          ],
          if (_message != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_message!,
                    style: TextStyle(
                        color: _messageIsError
                            ? theme.colorScheme.error
                            : Colors.green.shade800))),
        ]),
      ),
    );
  }
}
