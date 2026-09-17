import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';

class ClientsScreen extends StatefulWidget {
  final bool embedded;
  const ClientsScreen({super.key, this.embedded = false});
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  final search = TextEditingController();
  bool showInactive = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomerProvider>();
    final clients = provider.customers;
    final query = search.text.trim().toLowerCase();
    final filtered = clients
        .where((c) =>
            (showInactive || c.active) &&
            (query.isEmpty ||
                c.name.toLowerCase().contains(query) ||
                c.documentNumber.toLowerCase().contains(query)))
        .toList();
    final content = SafeArea(
        child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('Clientes',
                              style: GoogleFonts.poppins(
                                  color: const Color(0xFF2D2260),
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800)),
                          const Text(
                              'Datos comerciales y condición frente al IVA.',
                              style: TextStyle(color: Color(0xFF6B6589))),
                        ])),
                    FilledButton.icon(
                        onPressed: () => _openForm(),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Agregar cliente'))
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: search,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                hintText: 'Buscar por nombre o documento',
                                prefixIcon: Icon(Icons.search_rounded)))),
                    const SizedBox(width: 12),
                    FilterChip(
                        label: const Text('Mostrar inactivos'),
                        selected: showInactive,
                        onSelected: (v) {
                          setState(() => showInactive = v);
                          _load();
                        })
                  ]),
                  const SizedBox(height: 14),
                  Expanded(
                      child: provider.loading
                          ? const Center(child: CircularProgressIndicator())
                          : provider.error != null
                              ? Center(child: Text(provider.error!))
                              : filtered.isEmpty
                                  ? const Center(
                                      child:
                                          Text('No hay clientes para mostrar.'))
                                  : Card(
                                      margin: EdgeInsets.zero,
                                      elevation: 0,
                                      clipBehavior: Clip.antiAlias,
                                      child: ListView.separated(
                                          itemCount: filtered.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(height: 1),
                                          itemBuilder: (_, i) {
                                            final c = filtered[i];
                                            return ListTile(
                                                contentPadding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 18,
                                                        vertical: 5),
                                                leading: CircleAvatar(
                                                    backgroundColor:
                                                        const Color(0xFFEDE9FF),
                                                    child: Text(c.name.isEmpty
                                                        ? '?'
                                                        : c.name[0]
                                                            .toUpperCase())),
                                                title: Text(c.name,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700)),
                                                subtitle: Text(
                                                    '${c.vatCondition} · ${c.documentType} ${c.documentNumber}'),
                                                trailing: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Chip(
                                                          label: Text(c.active
                                                              ? 'Activo'
                                                              : 'Inactivo'),
                                                          backgroundColor: c
                                                                  .active
                                                              ? const Color(
                                                                  0xFFE8F5E9)
                                                              : const Color(
                                                                  0xFFEEEEEE)),
                                                      IconButton(
                                                          onPressed: () =>
                                                              _openForm(c),
                                                          tooltip: 'Editar',
                                                          icon: const Icon(Icons
                                                              .edit_outlined)),
                                                      IconButton(
                                                          onPressed: () =>
                                                              _toggleStatus(c),
                                                          tooltip: c.active
                                                              ? 'Desactivar'
                                                              : 'Activar',
                                                          icon: Icon(
                                                              c.active
                                                                  ? Icons
                                                                      .toggle_on_rounded
                                                                  : Icons
                                                                      .toggle_off_rounded,
                                                              size: 32,
                                                              color: c.active
                                                                  ? const Color(
                                                                      0xFF6DA544)
                                                                  : Colors
                                                                      .grey))
                                                    ]));
                                          })))
                ])));
    return widget.embedded
        ? ColoredBox(color: const Color(0xFFF5F5F8), child: content)
        : Scaffold(backgroundColor: const Color(0xFFF5F5F8), body: content);
  }

  Future<void> _load() => context.read<CustomerProvider>().load(
      context.read<AuthProvider>().session!.token,
      includeInactive: showInactive);

  Future<void> _toggleStatus(Customer customer) async {
    try {
      await context
          .read<CustomerProvider>()
          .setActive(customer, !customer.active);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _openForm([Customer? current]) async {
    final clients = context.read<CustomerProvider>().customers;
    final result = await showDialog<Customer>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ClientDialog(
            current: current,
            nextCode: clients.isEmpty
                ? 1
                : clients.map((c) => c.code).reduce((a, b) => a > b ? a : b) +
                    1));
    if (result == null || !mounted) return;
    try {
      await context.read<CustomerProvider>().save(result);
    } catch (error) {
      _showError(error);
    }
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', ''))));
  }
}

class _ClientDialog extends StatefulWidget {
  final Customer? current;
  final int nextCode;
  const _ClientDialog({this.current, required this.nextCode});
  @override
  State<_ClientDialog> createState() => _ClientDialogState();
}

class _ClientDialogState extends State<_ClientDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController name, document, phone, email;
  late String vatCondition, documentType;
  DateTime? birthday;
  static const conditions = [
    'Consumidor Final',
    'Responsable Inscripto',
    'Monotributista',
    'IVA Sujeto Exento',
    'Sin especificar'
  ];

  List<String> get documentTypes => vatCondition == 'Consumidor Final'
      ? ['DNI', 'CUIL', 'CDI', 'CUIT', 'Pasaporte', 'CI', 'Sin identificar']
      : vatCondition == 'Sin especificar'
          ? ['DNI', 'CUIT', 'CUIL', 'CDI', 'Pasaporte', 'CI']
          : ['CUIT'];

  @override
  void initState() {
    super.initState();
    final c = widget.current;
    name = TextEditingController(text: c?.name);
    document = TextEditingController(text: c?.documentNumber);
    phone = TextEditingController(text: c?.phone);
    email = TextEditingController(text: c?.email);
    vatCondition = c?.vatCondition ?? 'Consumidor Final';
    documentType = c?.documentType ?? 'DNI';
    birthday = c?.birthday;
  }

  @override
  void dispose() {
    name.dispose();
    document.dispose();
    phone.dispose();
    email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): () =>
                Navigator.pop(context),
            const SingleActivator(LogicalKeyboardKey.enter): _save,
          },
          child: Focus(
              autofocus: true,
              child: AlertDialog(
                  title: Text(widget.current == null
                      ? 'Agregar cliente'
                      : 'Editar cliente'),
                  content: Form(
                      key: formKey,
                      child: SizedBox(
                          width: 650,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Align(
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                        'Código: ${widget.current?.code ?? widget.nextCode}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700))),
                                const SizedBox(height: 12),
                                TextFormField(
                                    controller: name,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                        labelText: 'Nombre o razón social *'),
                                    validator: (v) =>
                                        v == null || v.trim().isEmpty
                                            ? 'Ingresá el nombre.'
                                            : null),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                    value: 'Predeterminada',
                                    decoration: const InputDecoration(
                                        labelText: 'Lista de precios'),
                                    items: const [
                                      DropdownMenuItem(
                                          value: 'Predeterminada',
                                          child: Text('Predeterminada'))
                                    ],
                                    onChanged: (_) {}),
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(
                                      child: DropdownButtonFormField<String>(
                                          value: vatCondition,
                                          decoration: const InputDecoration(
                                              labelText:
                                                  'Condición ante IVA *'),
                                          items: conditions
                                              .map((v) => DropdownMenuItem(
                                                  value: v, child: Text(v)))
                                              .toList(),
                                          onChanged: (v) => setState(() {
                                                vatCondition = v!;
                                                if (!documentTypes
                                                    .contains(documentType)) {
                                                  documentType =
                                                      documentTypes.first;
                                                }
                                              }))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: DropdownButtonFormField<String>(
                                          value: documentType,
                                          decoration: const InputDecoration(
                                              labelText: 'Tipo de documento *'),
                                          items: documentTypes
                                              .map((v) => DropdownMenuItem(
                                                  value: v, child: Text(v)))
                                              .toList(),
                                          onChanged: (v) => setState(
                                              () => documentType = v!)))
                                ]),
                                const SizedBox(height: 12),
                                TextFormField(
                                    controller: document,
                                    enabled: documentType != 'Sin identificar',
                                    decoration: InputDecoration(
                                        labelText: 'N.º de $documentType *'),
                                    validator: (v) =>
                                        documentType != 'Sin identificar' &&
                                                (v == null || v.trim().isEmpty)
                                            ? 'Ingresá el documento.'
                                            : null),
                                const SizedBox(height: 12),
                                Row(children: [
                                  Expanded(
                                      child: TextField(
                                          controller: phone,
                                          decoration: const InputDecoration(
                                              labelText: 'Teléfono'))),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: TextFormField(
                                          controller: email,
                                          decoration: const InputDecoration(
                                              labelText: 'Email'),
                                          validator: (v) => v != null &&
                                                  v.isNotEmpty &&
                                                  !v.contains('@')
                                              ? 'Email inválido.'
                                              : null))
                                ]),
                                const SizedBox(height: 12),
                                ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Cumpleaños'),
                                    subtitle: Text(birthday == null
                                        ? 'Sin especificar'
                                        : '${birthday!.day}/${birthday!.month}/${birthday!.year}'),
                                    trailing: const Icon(
                                        Icons.calendar_month_rounded),
                                    onTap: _pickBirthday),
                              ])))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    FilledButton(onPressed: _save, child: const Text('Guardar'))
                  ])));

  Future<void> _pickBirthday() async {
    final selected = await showDatePicker(
        context: context,
        initialDate: birthday ?? DateTime(1990),
        firstDate: DateTime(1900),
        lastDate: DateTime.now());
    if (selected != null) setState(() => birthday = selected);
  }

  void _save() {
    if (!formKey.currentState!.validate()) return;
    final old = widget.current;
    Navigator.pop(
        context,
        Customer(
            id: old?.id ?? 0,
            code: old?.code ?? widget.nextCode,
            name: name.text.trim(),
            vatCondition: vatCondition,
            documentType: documentType,
            documentNumber:
                documentType == 'Sin identificar' ? '' : document.text.trim(),
            phone: phone.text.trim(),
            email: email.text.trim(),
            birthday: birthday,
            active: old?.active ?? true));
  }
}
