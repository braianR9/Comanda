import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/google_sheet_provider.dart';

class GoogleSheetSettingsScreen extends StatefulWidget {
  final bool embedded;
  const GoogleSheetSettingsScreen({super.key, this.embedded = false});
  @override
  State<GoogleSheetSettingsScreen> createState() =>
      _GoogleSheetSettingsScreenState();
}

class _GoogleSheetSettingsScreenState extends State<GoogleSheetSettingsScreen> {
  final controller = TextEditingController();
  bool saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = context.read<AuthProvider>().session!.token;
    await context.read<GoogleSheetProvider>().load(token);
    if (!mounted) return;
    controller.text = context.read<GoogleSheetProvider>().sheetId ?? '';
  }

  Future<void> _save() async {
    if (saving) return;
    setState(() => saving = true);
    try {
      final token = context.read<AuthProvider>().session!.token;
      await context
          .read<GoogleSheetProvider>()
          .save(token, controller.text.trim());
      if (!mounted) return;
      controller.text = context.read<GoogleSheetProvider>().sheetId ?? '';
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Configuración guardada correctamente.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GoogleSheetProvider>();
    final content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Google Sheets',
                style: GoogleFonts.poppins(
                    color: const Color(0xFF2D2260),
                    fontSize: 25,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
                'Cada venta finalizada se agrega como una fila nueva a la planilla configurada.',
                style: TextStyle(color: Color(0xFF6B6589))),
            const SizedBox(height: 20),
            Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFE7E3F4)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!provider.loading && !provider.enabled)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 12),
                        child: Text(
                            'La sincronización todavía no está habilitada en el servidor. '
                            'Avisale a soporte para que la active antes de configurar tu planilla.',
                            style: TextStyle(color: Colors.red)),
                      ),
                    if (!provider.loading && provider.enabled) ...[
                      const Text(
                          '1. Abrí o creá tu planilla en Google Sheets.\n'
                          '2. Compartila (con permiso de Editor) con este email:',
                          style: TextStyle(color: Color(0xFF6B6589))),
                      const SizedBox(height: 8),
                      Row(children: [
                        Expanded(
                          child: SelectableText(
                              provider.serviceAccountEmail ?? 'Sin configurar',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w700)),
                        ),
                        if (provider.serviceAccountEmail != null)
                          IconButton(
                            tooltip: 'Copiar',
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            onPressed: () => Clipboard.setData(ClipboardData(
                                text: provider.serviceAccountEmail!)),
                          ),
                      ]),
                      const SizedBox(height: 8),
                      const Text('3. Pegá acá el link o el ID de esa planilla.',
                          style: TextStyle(color: Color(0xFF6B6589))),
                      const SizedBox(height: 16),
                    ],
                    if (provider.loading)
                      const Center(child: CircularProgressIndicator())
                    else ...[
                      TextField(
                        controller: controller,
                        decoration: const InputDecoration(
                          labelText: 'Link o ID de la planilla',
                          prefixIcon: Icon(Icons.table_chart_outlined),
                          hintText:
                              'https://docs.google.com/spreadsheets/d/...',
                        ),
                      ),
                      if (provider.error != null) ...[
                        const SizedBox(height: 8),
                        Text(provider.error!,
                            style: const TextStyle(color: Colors.red)),
                      ],
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: saving ? null : _save,
                          icon: saving
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.save_outlined),
                          label: const Text('Guardar'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return widget.embedded
        ? ColoredBox(color: const Color(0xFFF5F5F8), child: content)
        : Scaffold(backgroundColor: const Color(0xFFF5F5F8), body: content);
  }
}
