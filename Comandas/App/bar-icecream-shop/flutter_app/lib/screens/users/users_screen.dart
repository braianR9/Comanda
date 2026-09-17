import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/app_user.dart';
import '../../models/restaurant_table.dart';
import '../../models/sector.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sector_provider.dart';
import '../../providers/user_management_provider.dart';

class UsersScreen extends StatefulWidget {
  final bool embedded;
  const UsersScreen({super.key, this.embedded = false});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
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

  Future<void> _load() async {
    final token = context.read<AuthProvider>().session!.token;
    final provider = context.read<UserManagementProvider>();
    await Future.wait([
      provider.load(token, includeInactive: showInactive),
      provider.loadRoles(token),
      context.read<SectorProvider>().load(token: token),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<UserManagementProvider>();
    final query = search.text.trim().toLowerCase();
    final filtered = provider.users
        .where((u) =>
            (showInactive || u.active) &&
            (query.isEmpty ||
                u.fullName.toLowerCase().contains(query) ||
                u.email.toLowerCase().contains(query)))
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
                          Text('Usuarios',
                              style: GoogleFonts.poppins(
                                  color: const Color(0xFF2D2260),
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800)),
                          const Text('Empleados, encargados y administradores.',
                              style: TextStyle(color: Color(0xFF6B6589))),
                        ])),
                    FilledButton.icon(
                        onPressed:
                            provider.roles.isEmpty ? null : () => _openForm(),
                        icon: const Icon(Icons.person_add_alt_1_rounded),
                        label: const Text('Agregar usuario'))
                  ]),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                        child: TextField(
                            controller: search,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                                hintText: 'Buscar por nombre o email',
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
                                          Text('No hay usuarios para mostrar.'))
                                  : Card(
                                      margin: EdgeInsets.zero,
                                      elevation: 0,
                                      clipBehavior: Clip.antiAlias,
                                      child: ListView.separated(
                                          itemCount: filtered.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(height: 1),
                                          itemBuilder: (_, i) {
                                            final u = filtered[i];
                                            return ListTile(
                                                contentPadding: const EdgeInsets.symmetric(
                                                    horizontal: 18,
                                                    vertical: 5),
                                                leading: CircleAvatar(
                                                    backgroundColor:
                                                        const Color(0xFFEDE9FF),
                                                    child: Text(u.firstName.isEmpty
                                                        ? '?'
                                                        : u.firstName[0]
                                                            .toUpperCase())),
                                                title: Text(u.fullName,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700)),
                                                subtitle: Text(
                                                    '${u.email} · ${u.roleName}'),
                                                trailing: Row(
                                                    mainAxisSize: MainAxisSize.min,
                                                    children: [
                                                      Chip(
                                                          label: Text(u.active
                                                              ? 'Activo'
                                                              : 'Inactivo'),
                                                          backgroundColor: u
                                                                  .active
                                                              ? const Color(
                                                                  0xFFE8F5E9)
                                                              : const Color(
                                                                  0xFFEEEEEE)),
                                                      IconButton(
                                                          onPressed: () =>
                                                              _openForm(u),
                                                          tooltip: 'Editar',
                                                          icon: const Icon(Icons
                                                              .edit_outlined)),
                                                      IconButton(
                                                          onPressed: () =>
                                                              _toggleStatus(u),
                                                          tooltip: u.active
                                                              ? 'Desactivar'
                                                              : 'Activar',
                                                          icon: Icon(
                                                              u.active
                                                                  ? Icons
                                                                      .toggle_on_rounded
                                                                  : Icons
                                                                      .toggle_off_rounded,
                                                              size: 32,
                                                              color: u.active
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

  Future<void> _toggleStatus(AppUser user) async {
    try {
      await context
          .read<UserManagementProvider>()
          .setActive(user, !user.active);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _openForm([AppUser? current]) async {
    final roles = context.read<UserManagementProvider>().roles;
    final sectorProvider = context.read<SectorProvider>();
    final result = await showDialog<_UserFormResult>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _UserDialog(
            current: current,
            roles: roles,
            sectors: sectorProvider.sectors.where((s) => s.active).toList(),
            tables: sectorProvider.tables));
    if (result == null || !mounted) return;
    try {
      await context
          .read<UserManagementProvider>()
          .save(result.user, password: result.password);
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

class _UserFormResult {
  final AppUser user;
  final String? password;
  const _UserFormResult(this.user, this.password);
}

class _UserDialog extends StatefulWidget {
  final AppUser? current;
  final List<AppRole> roles;
  final List<Sector> sectors;
  final List<RestaurantTable> tables;
  const _UserDialog(
      {this.current,
      required this.roles,
      required this.sectors,
      required this.tables});
  @override
  State<_UserDialog> createState() => _UserDialogState();
}

class _UserDialogState extends State<_UserDialog> {
  final formKey = GlobalKey<FormState>();
  late final TextEditingController firstName, lastName, email, password;
  late int roleId;
  late bool active;
  late int? assignedSectorId;
  late Set<int> excludedTableIds;

  bool get _isEmpleado =>
      widget.roles.where((r) => r.id == roleId).firstOrNull?.name == 'EMPLEADO';

  @override
  void initState() {
    super.initState();
    final u = widget.current;
    firstName = TextEditingController(text: u?.firstName);
    lastName = TextEditingController(text: u?.lastName);
    email = TextEditingController(text: u?.email);
    password = TextEditingController();
    roleId = u?.roleId ?? widget.roles.first.id;
    active = u?.active ?? true;
    assignedSectorId = u?.assignedSectorId;
    excludedTableIds = {...?u?.excludedTableIds};
  }

  @override
  void dispose() {
    firstName.dispose();
    lastName.dispose();
    email.dispose();
    password.dispose();
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
                      ? 'Agregar usuario'
                      : 'Editar usuario'),
                  content: Form(
                      key: formKey,
                      child: SizedBox(
                          width: 500,
                          child: SingleChildScrollView(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Row(children: [
                                  Expanded(
                                      child: TextFormField(
                                          controller: firstName,
                                          autofocus: true,
                                          decoration: const InputDecoration(
                                              labelText: 'Nombre *'),
                                          validator: (v) =>
                                              v == null || v.trim().isEmpty
                                                  ? 'Ingresá el nombre.'
                                                  : null)),
                                  const SizedBox(width: 12),
                                  Expanded(
                                      child: TextFormField(
                                          controller: lastName,
                                          decoration: const InputDecoration(
                                              labelText: 'Apellido *'),
                                          validator: (v) =>
                                              v == null || v.trim().isEmpty
                                                  ? 'Ingresá el apellido.'
                                                  : null)),
                                ]),
                                const SizedBox(height: 12),
                                TextFormField(
                                    controller: email,
                                    decoration: const InputDecoration(
                                        labelText: 'Email *'),
                                    validator: (v) => v == null ||
                                            v.trim().isEmpty ||
                                            !v.contains('@')
                                        ? 'Ingresá un email válido.'
                                        : null),
                                const SizedBox(height: 12),
                                TextFormField(
                                    controller: password,
                                    obscureText: true,
                                    decoration: InputDecoration(
                                        labelText: widget.current == null
                                            ? 'Contraseña *'
                                            : 'Nueva contraseña (opcional)'),
                                    validator: (v) {
                                      if (widget.current == null &&
                                          (v == null || v.trim().isEmpty)) {
                                        return 'Ingresá una contraseña.';
                                      }
                                      if (v != null &&
                                          v.isNotEmpty &&
                                          v.trim().length < 6) {
                                        return 'Debe tener al menos 6 caracteres.';
                                      }
                                      return null;
                                    }),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<int>(
                                    value: roleId,
                                    decoration: const InputDecoration(
                                        labelText: 'Rol *'),
                                    items: widget.roles
                                        .map((r) => DropdownMenuItem(
                                            value: r.id, child: Text(r.name)))
                                        .toList(),
                                    onChanged: (v) =>
                                        setState(() => roleId = v!)),
                                if (_isEmpleado) ...[
                                  const SizedBox(height: 12),
                                  DropdownButtonFormField<int?>(
                                      value: assignedSectorId,
                                      decoration: const InputDecoration(
                                          labelText: 'Sector asignado'),
                                      items: [
                                        const DropdownMenuItem(
                                            value: null,
                                            child: Text('Todos los sectores')),
                                        for (final sector in widget.sectors)
                                          DropdownMenuItem(
                                              value: sector.id,
                                              child: Text(sector.name)),
                                      ],
                                      onChanged: (v) => setState(() {
                                            assignedSectorId = v;
                                            excludedTableIds = {};
                                          })),
                                  if (assignedSectorId != null) ...[
                                    const SizedBox(height: 8),
                                    Align(
                                        alignment: Alignment.centerLeft,
                                        child: Text(
                                            'Mesas visibles en el sector',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge)),
                                    for (final table in widget.tables.where(
                                        (t) => t.sectorId == assignedSectorId))
                                      CheckboxListTile(
                                          dense: true,
                                          contentPadding: EdgeInsets.zero,
                                          controlAffinity:
                                              ListTileControlAffinity.leading,
                                          title: Text(table.name),
                                          value: !excludedTableIds
                                              .contains(table.id),
                                          onChanged: (checked) => setState(() {
                                                if (checked == true) {
                                                  excludedTableIds
                                                      .remove(table.id);
                                                } else {
                                                  excludedTableIds
                                                      .add(table.id);
                                                }
                                              })),
                                  ],
                                ],
                                const SizedBox(height: 4),
                                SwitchListTile(
                                    contentPadding: EdgeInsets.zero,
                                    title: const Text('Activo'),
                                    value: active,
                                    onChanged: (v) =>
                                        setState(() => active = v)),
                              ])))),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancelar')),
                    FilledButton(onPressed: _save, child: const Text('Guardar'))
                  ])));

  void _save() {
    if (!formKey.currentState!.validate()) return;
    final user = AppUser(
      id: widget.current?.id ?? 0,
      firstName: firstName.text.trim(),
      lastName: lastName.text.trim(),
      email: email.text.trim(),
      roleId: roleId,
      active: active,
      assignedSectorId: _isEmpleado ? assignedSectorId : null,
      excludedTableIds: _isEmpleado && assignedSectorId != null
          ? excludedTableIds.toList()
          : const [],
    );
    Navigator.pop(
        context,
        _UserFormResult(
            user, password.text.trim().isEmpty ? null : password.text.trim()));
  }
}
