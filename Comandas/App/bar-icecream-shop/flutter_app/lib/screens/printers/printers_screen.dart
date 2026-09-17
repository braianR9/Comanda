import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';

class PrintersScreen extends StatefulWidget {
  final bool embedded;
  const PrintersScreen({super.key, this.embedded = false});

  @override
  State<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends State<PrintersScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = context.read<AuthProvider>().session?.token;
      if (token != null) context.read<PrinterProvider>().load(token);
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = Consumer<PrinterProvider>(builder: (_, provider, __) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Impresoras',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF302568))),
                    SizedBox(height: 4),
                    Text(
                        'Configurá dónde se imprimen las comandas y los tickets de venta.',
                        style: TextStyle(color: Color(0xFF747386))),
                  ]),
            ),
            FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Nueva impresora'),
            ),
          ]),
          const SizedBox(height: 24),
          if (provider.loading && provider.printers.isEmpty)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (provider.error != null && provider.printers.isEmpty)
            Expanded(
                child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.print_disabled_outlined,
                  size: 48, color: Color(0xFF9E8FCC)),
              const SizedBox(height: 12),
              Text(provider.error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _reload, child: const Text('Reintentar')),
            ])))
          else if (provider.printers.isEmpty)
            const Expanded(
                child: Center(
                    child: Text('Todavía no hay impresoras configuradas.')))
          else
            Expanded(
                child: ListView.separated(
              itemCount: provider.printers.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, index) => _PrinterCard(
                printer: provider.printers[index],
                onEdit: () => _edit(provider.printers[index]),
                onTest: () => _test(provider.printers[index]),
                onActiveChanged: (active) =>
                    _setActive(provider.printers[index], active),
              ),
            )),
        ]),
      );
    });
    return widget.embedded
        ? content
        : Scaffold(
            appBar: AppBar(title: const Text('Impresoras')), body: content);
  }

  void _reload() {
    final token = context.read<AuthProvider>().session?.token;
    if (token != null) context.read<PrinterProvider>().load(token);
  }

  Future<void> _edit([ConfiguredPrinter? printer]) async {
    final value = await showDialog<ConfiguredPrinter>(
        context: context, builder: (_) => _PrinterDialog(printer: printer));
    if (value == null || !mounted) return;
    try {
      await context.read<PrinterProvider>().save(value);
      if (mounted) _message('Impresora guardada correctamente.');
    } catch (error) {
      if (mounted) {
        _message(error.toString().replaceFirst('Exception: ', ''), error: true);
      }
    }
  }

  Future<void> _test(ConfiguredPrinter printer) async {
    try {
      await context.read<PrinterProvider>().test(printer);
      if (mounted) _message('Prueba enviada a ${printer.name}.');
    } catch (error) {
      if (mounted) {
        _message(error.toString().replaceFirst('Exception: ', ''), error: true);
      }
    }
  }

  Future<void> _setActive(ConfiguredPrinter printer, bool active) async {
    try {
      await context.read<PrinterProvider>().setActive(printer, active);
    } catch (error) {
      if (mounted) {
        _message(error.toString().replaceFirst('Exception: ', ''), error: true);
      }
    }
  }

  void _message(String value, {bool error = false}) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(value),
          backgroundColor: error ? Colors.red.shade700 : null));
}

class _PrinterCard extends StatelessWidget {
  final ConfiguredPrinter printer;
  final VoidCallback onEdit;
  final VoidCallback onTest;
  final ValueChanged<bool> onActiveChanged;
  const _PrinterCard(
      {required this.printer,
      required this.onEdit,
      required this.onTest,
      required this.onActiveChanged});

  @override
  Widget build(BuildContext context) {
    final destination = printer.connectionType == 'Cups'
        ? 'Cola: ${printer.queueName}'
        : '${printer.ipAddress}:${printer.port}';
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE4E1EE))),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(children: [
          Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: printer.active
                      ? const Color(0xFFEDE9FF)
                      : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.print_rounded,
                  color:
                      printer.active ? const Color(0xFF6C5CE7) : Colors.grey)),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(printer.name,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF302568))),
                      if (printer.isDefault)
                        const Chip(
                            label: Text('Predeterminada'),
                            visualDensity: VisualDensity.compact),
                      if (!printer.active)
                        const Chip(
                            label: Text('Inactiva'),
                            visualDensity: VisualDensity.compact),
                    ]),
                const SizedBox(height: 5),
                Text(
                    '${printer.connectionType} · $destination · Uso: ${_usage(printer.usage)}',
                    style: const TextStyle(color: Color(0xFF747386))),
              ])),
          IconButton(
              tooltip: 'Imprimir prueba',
              onPressed: printer.active ? onTest : null,
              icon: const Icon(Icons.receipt_long_outlined)),
          IconButton(
              tooltip: 'Editar',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined)),
          Switch(value: printer.active, onChanged: onActiveChanged),
        ]),
      ),
    );
  }

  static String _usage(String value) => value == 'TicketVenta'
      ? 'Ticket'
      : value == 'Comanda'
          ? 'Comanda'
          : 'Comanda - Ticket';
}

class _PrinterDialog extends StatefulWidget {
  final ConfiguredPrinter? printer;
  const _PrinterDialog({this.printer});

  @override
  State<_PrinterDialog> createState() => _PrinterDialogState();
}

class _PrinterDialogState extends State<_PrinterDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _queue;
  late final TextEditingController _ip;
  late final TextEditingController _port;
  late String _connection;
  late String _usage;
  late bool _default;
  late bool _active;

  @override
  void initState() {
    super.initState();
    final value = widget.printer;
    _name = TextEditingController(text: value?.name ?? '');
    _queue = TextEditingController(text: value?.queueName ?? 'Printer_POS_80C');
    _ip = TextEditingController(text: value?.ipAddress ?? '');
    _port = TextEditingController(text: '${value?.port ?? 9100}');
    _connection = value?.connectionType ?? 'Cups';
    _usage = value?.usage ?? 'Ambos';
    _default = value?.isDefault ?? true;
    _active = value?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _queue.dispose();
    _ip.dispose();
    _port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(
            widget.printer == null ? 'Nueva impresora' : 'Editar impresora'),
        content: SizedBox(
            width: 520,
            child: Form(
                key: _formKey,
                child: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(labelText: 'Nombre'),
                      validator: _required),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                      value: _connection,
                      decoration:
                          const InputDecoration(labelText: 'Tipo de conexión'),
                      items: const [
                        DropdownMenuItem(
                            value: 'Cups', child: Text('USB / cola CUPS')),
                        DropdownMenuItem(value: 'Red', child: Text('Red (IP)'))
                      ],
                      onChanged: (value) =>
                          setState(() => _connection = value!)),
                  const SizedBox(height: 14),
                  if (_connection == 'Cups')
                    TextFormField(
                        controller: _queue,
                        decoration: const InputDecoration(
                            labelText: 'Nombre de la cola',
                            helperText: 'Ejemplo: Printer_POS_80C'),
                        validator: _required)
                  else
                    Row(children: [
                      Expanded(
                          child: TextFormField(
                              controller: _ip,
                              decoration: const InputDecoration(
                                  labelText: 'Dirección IP'),
                              validator: _required)),
                      const SizedBox(width: 12),
                      SizedBox(
                          width: 130,
                          child: TextFormField(
                              controller: _port,
                              keyboardType: TextInputType.number,
                              decoration:
                                  const InputDecoration(labelText: 'Puerto'),
                              validator: (value) {
                                final port = int.tryParse(value ?? '');
                                return port == null || port < 1 || port > 65535
                                    ? 'Inválido'
                                    : null;
                              })),
                    ]),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                      value: _usage,
                      decoration: const InputDecoration(labelText: 'Usar para'),
                      items: const [
                        DropdownMenuItem(
                            value: 'Comanda', child: Text('Comanda')),
                        DropdownMenuItem(
                            value: 'TicketVenta', child: Text('Ticket')),
                        DropdownMenuItem(
                            value: 'Ambos', child: Text('Comanda - Ticket'))
                      ],
                      onChanged: (value) => setState(() => _usage = value!)),
                  const SizedBox(height: 8),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Impresora predeterminada'),
                      subtitle: const Text(
                          'Se elegirá automáticamente para este uso.'),
                      value: _default,
                      onChanged: (value) => setState(() => _default = value)),
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Activa'),
                      value: _active,
                      onChanged: (value) => setState(() => _active = value)),
                ])))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Guardar'))
        ],
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio' : null;
  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
        context,
        ConfiguredPrinter(
          id: widget.printer?.id ?? 0,
          name: _name.text.trim(),
          connectionType: _connection,
          queueName: _connection == 'Cups' ? _queue.text.trim() : null,
          ipAddress: _connection == 'Red' ? _ip.text.trim() : null,
          port: _connection == 'Red' ? int.parse(_port.text) : null,
          usage: _usage,
          isDefault: _default,
          active: _active,
        ));
  }
}
