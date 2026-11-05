import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/printer_provider.dart';
import '../../theme/brand_colors.dart';
import '../../utils/file_download.dart';

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
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Impresoras',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: Brand.ink)),
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
              Icon(Icons.print_disabled_outlined, size: 48, color: Brand.muted),
              const SizedBox(height: 12),
              Text(provider.error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                  onPressed: _reload, child: const Text('Reintentar')),
            ])))
          else
            Expanded(
                child: ListView(children: [
              _AgentsCard(
                agents: provider.agents,
                onAdd: _addAgent,
                onRegenerateKey: _regenerateAgentKey,
                onRename: _renameAgent,
                onDelete: _deleteAgent,
                onDownload: _downloadAgent,
              ),
              const SizedBox(height: 20),
              if (provider.printers.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                        child: Text('Todavía no hay impresoras configuradas.')))
              else
                for (final printer in provider.printers) ...[
                  _PrinterCard(
                    printer: printer,
                    agentName: _agentName(provider.agents, printer),
                    onEdit: () => _edit(printer),
                    onTest: () => _test(printer),
                    onActiveChanged: (active) => _setActive(printer, active),
                  ),
                  const SizedBox(height: 12),
                ],
            ])),
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
        context: context,
        builder: (_) => _PrinterDialog(
            printer: printer, agents: context.read<PrinterProvider>().agents));
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

  /// Computadora que imprime en esta impresora; sin asignar, la primera agregada.
  static String? _agentName(
      List<PrintAgentInfo> agents, ConfiguredPrinter printer) {
    if (agents.isEmpty) return null;
    for (final agent in agents) {
      if (agent.id == printer.agentId) return agent.name;
    }
    return agents.first.name;
  }

  Future<void> _addAgent() async {
    final name = await _askAgentName('Agregar computadora');
    if (name == null || !mounted) return;
    await _showKey(() => context.read<PrinterProvider>().createAgent(name));
  }

  Future<void> _regenerateAgentKey(PrintAgentInfo agent) async {
    if (!await _confirm(
        '¿Generar una clave nueva para ${agent.name}?',
        'El agente instalado en esa computadora deja de imprimir hasta que lo instales de nuevo con la clave nueva.',
        'Generar')) {
      return;
    }
    if (!mounted) return;
    await _showKey(
        () => context.read<PrinterProvider>().regenerateAgentKey(agent));
  }

  Future<void> _renameAgent(PrintAgentInfo agent) async {
    final name =
        await _askAgentName('Cambiar nombre', initialValue: agent.name);
    if (name == null || !mounted) return;
    await _run(() => context.read<PrinterProvider>().renameAgent(agent, name));
  }

  Future<void> _deleteAgent(PrintAgentInfo agent) async {
    if (!await _confirm(
        '¿Quitar ${agent.name}?',
        'Su clave deja de funcionar y sus impresoras pasan a la primera computadora de la lista. '
            'En esa computadora podés desinstalar el agente con "desinstalar".',
        'Quitar')) {
      return;
    }
    if (!mounted) return;
    await _run(() => context.read<PrinterProvider>().deleteAgent(agent));
  }

  Future<void> _showKey(Future<String> Function() createKey) async {
    try {
      final key = await createKey();
      if (!mounted) return;
      await showDialog<void>(
          context: context, builder: (_) => _AgentKeyDialog(agentKey: key));
    } catch (error) {
      if (mounted) {
        _message(error.toString().replaceFirst('Exception: ', ''), error: true);
      }
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        _message(error.toString().replaceFirst('Exception: ', ''), error: true);
      }
    }
  }

  Future<bool> _confirm(String title, String content, String action) async =>
      await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                title: Text(title),
                content: Text(content),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(action)),
                ],
              )) ==
      true;

  Future<String?> _askAgentName(String title, {String initialValue = ''}) {
    final controller = TextEditingController(text: initialValue);
    void submit(BuildContext context) {
      final name = controller.text.trim();
      if (name.isNotEmpty) Navigator.pop(context, name);
    }

    return showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 420,
                child: TextField(
                    controller: controller,
                    autofocus: true,
                    maxLength: 100,
                    decoration: const InputDecoration(
                        labelText: 'Nombre',
                        helperText: 'Por ejemplo: Caja, Cocina, Barra'),
                    onSubmitted: (_) => submit(context)),
              ),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () => submit(context),
                    child: const Text('Guardar')),
              ],
            )).whenComplete(controller.dispose);
  }

  Future<void> _downloadAgent(String fileName) async {
    _message('Descargando $fileName…');
    try {
      final bytes =
          await context.read<PrinterProvider>().downloadAgent(fileName);
      final saved = await saveExcelFile(fileName, bytes,
          dialogTitle: 'Guardar instalador',
          extension: 'zip',
          mimeType: 'application/zip');
      if (saved != null && mounted) _message('Instalador descargado.');
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
  final String? agentName;
  final VoidCallback onEdit;
  final VoidCallback onTest;
  final ValueChanged<bool> onActiveChanged;
  const _PrinterCard(
      {required this.printer,
      this.agentName,
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
          side: BorderSide(color: Brand.surface)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(children: [
          Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                  color: printer.active ? Brand.tint : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.print_rounded,
                  color: printer.active ? Brand.primary : Colors.grey)),
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
                          style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Brand.ink)),
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
                    '${printer.connectionType} · $destination · Uso: ${_usage(printer.usage)}'
                    '${agentName == null ? '' : ' · Computadora: $agentName'}',
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
  final List<PrintAgentInfo> agents;
  const _PrinterDialog({this.printer, this.agents = const []});

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
  int? _agentId;

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
    final agents = widget.agents;
    _agentId = agents.any((x) => x.id == value?.agentId)
        ? value!.agentId
        : agents.length == 1
            ? agents.first.id
            : null;
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
                            value: 'Cups',
                            child: Text('USB / impresora del sistema')),
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
                            helperText:
                                'Tal cual lo muestra el instalador del agente'),
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
                  if (widget.agents.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    DropdownButtonFormField<int>(
                        initialValue: _agentId,
                        decoration: const InputDecoration(
                            labelText: 'Computadora que la imprime',
                            helperText:
                                'La computadora a la que está enchufada la impresora'),
                        items: [
                          for (final agent in widget.agents)
                            DropdownMenuItem(
                                value: agent.id, child: Text(agent.name))
                        ],
                        validator: (value) =>
                            value == null ? 'Elegí la computadora' : null,
                        onChanged: (value) => setState(() => _agentId = value)),
                  ],
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
          agentId: _agentId,
        ));
  }
}

/// Computadoras del local con el agente instalado: estado, claves e instaladores.
class _AgentsCard extends StatelessWidget {
  final List<PrintAgentInfo> agents;
  final VoidCallback onAdd;
  final ValueChanged<PrintAgentInfo> onRegenerateKey;
  final ValueChanged<PrintAgentInfo> onRename;
  final ValueChanged<PrintAgentInfo> onDelete;
  final ValueChanged<String> onDownload;
  const _AgentsCard(
      {required this.agents,
      required this.onAdd,
      required this.onRegenerateKey,
      required this.onRename,
      required this.onDelete,
      required this.onDownload});

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Brand.surface)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                      color: Brand.tint,
                      borderRadius: BorderRadius.circular(12)),
                  child: Icon(Icons.computer_rounded, color: Brand.primary)),
              const SizedBox(width: 16),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Computadoras con impresoras',
                        style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: Brand.ink)),
                    const SizedBox(height: 3),
                    const Text(
                        'En cada computadora que tenga impresoras enchufadas se instala el agente de impresión. '
                        'Las demás (mozos, celulares) no necesitan nada.',
                        style: TextStyle(color: Color(0xFF747386))),
                  ])),
            ]),
            const SizedBox(height: 12),
            if (agents.isEmpty)
              const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: Text('Todavía no agregaste ninguna computadora.'))
            else
              for (final agent in agents) _agentRow(agent),
            const SizedBox(height: 12),
            Wrap(spacing: 10, runSpacing: 10, children: [
              FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Agregar computadora')),
              OutlinedButton.icon(
                  onPressed: () => onDownload('FocoAgente-Windows.zip'),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Descargar para Windows')),
              OutlinedButton.icon(
                  onPressed: () => onDownload('FocoAgente-Mac.zip'),
                  icon: const Icon(Icons.download_rounded),
                  label: const Text('Descargar para Mac')),
            ]),
            const SizedBox(height: 4),
            Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 12),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                initiallyExpanded: agents.isEmpty,
                title: Text('Cómo dejar las impresoras funcionando',
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: Brand.primary)),
                children: const [
                  _Step(
                      1,
                      'Enchufá cada impresora por USB a la computadora que tenga más cerca. '
                      'Por ejemplo, la de comandas a la PC de la cocina y la de tickets a la PC de la caja.'),
                  _Step(2,
                      'Tocá "Agregar computadora" por cada PC que tenga impresoras, ponele un nombre (Caja, Cocina) y copiá su clave. Se muestra una sola vez.'),
                  _Step(3,
                      'En cada una de esas PCs, entrá a Foco, descargá el instalador (Windows o Mac) y descomprimilo.'),
                  _Step(
                      4,
                      'Abrí "instalar" (en Windows instalar.cmd, en Mac instalar.command), pegá la clave de ESA computadora y apretá Enter. '
                      'En unos segundos aparece como "Conectada".'),
                  _Step(
                      5,
                      'El instalador muestra los nombres de las impresoras de esa PC. Cargá cada una acá con "Nueva impresora": '
                      'tipo "USB / impresora del sistema", el nombre exacto en "Nombre de la cola", para qué se usa y la computadora a la que está enchufada.'),
                  _Step(6,
                      'Tocá el ícono de prueba de cada impresora. Si sale el ticket "PRUEBA DE IMPRESION", ya está.'),
                  SizedBox(height: 8),
                  Text(
                      'Si Windows muestra "Windows protegió su PC", tocá "Más información" y "Ejecutar de todas formas". '
                      'Si la Mac no lo deja abrir, andá a Configuración del Sistema > Privacidad y seguridad > "Abrir igualmente".',
                      style: TextStyle(color: Color(0xFF747386), fontSize: 13)),
                ],
              ),
            ),
          ]),
        ),
      );

  Widget _agentRow(PrintAgentInfo agent) {
    final (color, text) = agent.connected
        ? (Colors.green.shade700, 'Conectada · ${agent.machine ?? ''}')
        : agent.lastSeen == null
            ? (Colors.orange.shade800, 'Falta instalar el agente')
            : (
                Colors.orange.shade800,
                'Sin conexión desde el ${_date(agent.lastSeen!)}'
                    '${agent.machine == null ? '' : ' · ${agent.machine}'}'
              );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Icon(Icons.circle, size: 10, color: color),
        const SizedBox(width: 10),
        Text(agent.name,
            style: TextStyle(fontWeight: FontWeight.w700, color: Brand.ink)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        PopupMenuButton<String>(
          tooltip: 'Opciones',
          onSelected: (value) => switch (value) {
            'key' => onRegenerateKey(agent),
            'rename' => onRename(agent),
            _ => onDelete(agent),
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'key', child: Text('Generar clave nueva')),
            PopupMenuItem(value: 'rename', child: Text('Cambiar nombre')),
            PopupMenuItem(value: 'delete', child: Text('Quitar')),
          ],
        ),
      ]),
    );
  }

  static String _date(DateTime value) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(value.day)}/${two(value.month)} a las ${two(value.hour)}:${two(value.minute)}';
  }
}

class _Step extends StatelessWidget {
  final int number;
  final String text;
  const _Step(this.number, this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
              radius: 11,
              backgroundColor: Brand.tint,
              child: Text('$number',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Brand.primary))),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ]),
      );
}

class _AgentKeyDialog extends StatelessWidget {
  final String agentKey;
  const _AgentKeyDialog({required this.agentKey});

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Clave de la computadora'),
        content: SizedBox(
          width: 520,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text(
                'Copiala y pegala cuando el instalador la pida. Por seguridad no se vuelve a mostrar: '
                'si la perdés, generá otra.'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                  color: Brand.tint, borderRadius: BorderRadius.circular(10)),
              child: SelectableText(agentKey,
                  style: const TextStyle(
                      fontFamily: 'monospace', fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
          FilledButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: agentKey));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Clave copiada.')));
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copiar clave')),
        ],
      );
}
