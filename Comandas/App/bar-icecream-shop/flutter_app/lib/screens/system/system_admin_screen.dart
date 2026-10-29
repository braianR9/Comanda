import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/system_admin_provider.dart';

class SystemAdminScreen extends StatelessWidget {
  final SystemAdminProvider Function()? createProvider;
  const SystemAdminScreen({super.key, this.createProvider});
  @override
  Widget build(BuildContext context) => ChangeNotifierProvider(
        create: (_) => createProvider?.call() ?? SystemAdminProvider(),
        child: const _SystemPanel(),
      );
}

const _sections = [
  'Empresas',
  'Usuarios',
  'Transacciones',
  'Errores',
  'Auditoría'
];
const _icons = [
  Icons.business_outlined,
  Icons.people_outline,
  Icons.receipt_long_outlined,
  Icons.bug_report_outlined,
  Icons.history
];

class _SystemPanel extends StatelessWidget {
  const _SystemPanel();
  @override
  Widget build(BuildContext context) {
    final model = context.watch<SystemAdminProvider>();
    if (!model.authenticated) return const _SystemLogin();
    final wide = MediaQuery.sizeOf(context).width >= 950;
    return Scaffold(
      appBar: AppBar(
        title: const Text('focobr · Sistemas'),
        actions: [
          if (wide) Center(child: Text(model.email)),
          IconButton(
              tooltip: 'Cambiar mi contraseña',
              icon: const Icon(Icons.password),
              onPressed: () => _password(context)),
          IconButton(
              tooltip: 'Cerrar sesión de sistemas',
              icon: const Icon(Icons.logout),
              onPressed: model.logout),
        ],
      ),
      body: Row(children: [
        if (wide)
          NavigationRail(
            extended: true,
            selectedIndex: model.section,
            onDestinationSelected: model.busy ? null : model.changeSection,
            destinations: [
              for (var i = 0; i < _sections.length; i++)
                NavigationRailDestination(
                    icon: Icon(_icons[i]), label: Text(_sections[i]))
            ],
          ),
        Expanded(
            child: Column(children: [
          _Filters(model: model),
          if (model.busy) const LinearProgressIndicator(),
          if (model.error != null)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(model.error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
          if (model.section == 2 && !model.busy)
            _TransactionSummary(model: model),
          Expanded(
              child: model.rows.isEmpty
                  ? Center(
                      child: Text(model.busy
                          ? 'Cargando…'
                          : model.section == 1 && model.companyId == null
                              ? 'Elegí una empresa para gestionar sus usuarios.'
                              : 'No hay resultados para estos filtros.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: model.rows.length,
                      itemBuilder: (_, i) =>
                          _ResultCard(model: model, row: model.rows[i]),
                    )),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Expanded(
                    child: Text(
                        '${model.total} resultados · Página ${model.page}')),
                IconButton(
                    tooltip: 'Página anterior',
                    onPressed: model.busy || model.page <= 1
                        ? null
                        : () {
                            model.page--;
                            model.load();
                          },
                    icon: const Icon(Icons.chevron_left)),
                IconButton(
                    tooltip: 'Página siguiente',
                    onPressed: model.busy || !model.hasNext
                        ? null
                        : () {
                            model.page++;
                            model.load();
                          },
                    icon: const Icon(Icons.chevron_right)),
              ])),
        ])),
      ]),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: model.section,
              onDestinationSelected: model.busy ? null : model.changeSection,
              destinations: [
                for (var i = 0; i < _sections.length; i++)
                  NavigationDestination(
                      icon: Icon(_icons[i]), label: _sections[i])
              ],
            ),
    );
  }

  Future<void> _password(BuildContext context) async {
    final values = await _form(context, 'Cambiar mi contraseña', const [
      _Field('current', 'Contraseña actual', password: true, required: true),
      _Field('next', 'Contraseña nueva (mínimo 12 caracteres)',
          password: true, required: true, minLength: 12),
      _Field('repeat', 'Repetir contraseña nueva',
          password: true, required: true, minLength: 12),
    ]);
    if (values == null || !context.mounted) return;
    if (values['next'] != values['repeat']) {
      _notice(context, 'Las contraseñas nuevas no coinciden.');
      return;
    }
    await _run(
        context,
        () => context.read<SystemAdminProvider>().changePassword(
            values['current'] as String, values['next'] as String));
  }
}

class _SystemLogin extends StatefulWidget {
  const _SystemLogin();
  @override
  State<_SystemLogin> createState() => _SystemLoginState();
}

class _SystemLoginState extends State<_SystemLogin> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _hidden = true;
  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_form.currentState!.validate()) return;
    await context
        .read<SystemAdminProvider>()
        .login(_email.text, _password.text);
    if (mounted) _password.clear();
  }

  @override
  Widget build(BuildContext context) {
    final model = context.watch<SystemAdminProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso de sistemas')),
      body: Center(
          child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: 440,
                child: Card(
                    child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Form(
                            key: _form,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const Icon(Icons.admin_panel_settings_outlined,
                                    size: 52),
                                const SizedBox(height: 16),
                                Text('Administración de focobr',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall),
                                const SizedBox(height: 8),
                                const Text(
                                    'Acceso exclusivo del propietario del sistema.'),
                                const SizedBox(height: 24),
                                TextFormField(
                                    controller: _email,
                                    enabled: !model.busy,
                                    keyboardType: TextInputType.emailAddress,
                                    autofillHints: const [
                                      AutofillHints.username
                                    ],
                                    textInputAction: TextInputAction.next,
                                    decoration: const InputDecoration(
                                        labelText: 'Correo de sistemas'),
                                    validator: (v) => v?.contains('@') == true
                                        ? null
                                        : 'Ingresá un correo válido.'),
                                const SizedBox(height: 16),
                                TextFormField(
                                    controller: _password,
                                    enabled: !model.busy,
                                    obscureText: _hidden,
                                    autofillHints: const [
                                      AutofillHints.password
                                    ],
                                    onFieldSubmitted: (_) {
                                      if (!model.busy) _login();
                                    },
                                    decoration: InputDecoration(
                                        labelText: 'Contraseña',
                                        suffixIcon: IconButton(
                                            onPressed: () => setState(
                                                () => _hidden = !_hidden),
                                            icon: Icon(_hidden
                                                ? Icons.visibility_outlined
                                                : Icons
                                                    .visibility_off_outlined))),
                                    validator: (v) => v == null || v.isEmpty
                                        ? 'Ingresá la contraseña.'
                                        : null),
                                if (model.error != null)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 16),
                                      child: Text(model.error!,
                                          style: TextStyle(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .error))),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                    onPressed: model.busy ? null : _login,
                                    child: Text(model.busy
                                        ? 'Ingresando…'
                                        : 'Ingresar a sistemas')),
                              ],
                            )))),
              ))),
    );
  }
}

class _Filters extends StatelessWidget {
  final SystemAdminProvider model;
  const _Filters({required this.model});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(16),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(_sections[model.section],
                    style: Theme.of(context).textTheme.titleLarge),
                if (model.section != 0)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.business_outlined),
                    label: Text(model.companyId == null
                        ? 'Todas las empresas'
                        : model.companies.first['nombre'] as String),
                    onPressed: model.busy
                        ? null
                        : () async {
                            final chosen =
                                await showDialog<Map<String, dynamic>>(
                                    context: context,
                                    builder: (_) =>
                                        _CompanyPicker(model: model));
                            if (chosen != null) {
                              if (!context.mounted) return;
                              await _run(
                                  context, () => model.selectCompany(chosen));
                            }
                          },
                  ),
                if (model.section != 0 && model.companyId != null)
                  TextButton(
                    onPressed: model.busy
                        ? null
                        : () {
                            model.companyId = null;
                            model.branchId = null;
                            model.branches = [];
                            model.page = 1;
                            model.load();
                          },
                    child: const Text('Quitar filtro de empresa'),
                  ),
                if (model.section >= 2 && model.companyId != null)
                  SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<int>(
                        key: ValueKey(
                            'branch-${model.companyId}-${model.branchId}'),
                        initialValue: model.branchId,
                        decoration:
                            const InputDecoration(labelText: 'Sucursal'),
                        isExpanded: true,
                        items: [
                          const DropdownMenuItem<int>(
                              value: null, child: Text('Todas las sucursales')),
                          for (final b in model.branches)
                            DropdownMenuItem(
                                value: b['id'] as int,
                                child: Text(b['nombre'] as String))
                        ],
                        onChanged: model.busy
                            ? null
                            : (id) {
                                model.branchId = id;
                                model.page = 1;
                                model.load();
                              },
                      )),
                if (model.section == 0 ||
                    model.section == 1 && model.companyId != null)
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: Text(
                        model.section == 0 ? 'Nueva empresa' : 'Nuevo usuario'),
                    onPressed: model.busy
                        ? null
                        : () => model.section == 0
                            ? _editCompany(context, model)
                            : _editUser(context, model),
                  ),
                IconButton(
                    tooltip: 'Actualizar',
                    onPressed: model.busy ? null : model.load,
                    icon: const Icon(Icons.refresh)),
              ]),
          const SizedBox(height: 12),
          Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (model.section != 2)
                  SizedBox(
                      width: 300,
                      child: TextFormField(
                        key: ValueKey(
                            'search-${model.section}-${model.companyId}'),
                        initialValue: model.search,
                        decoration: InputDecoration(
                            labelText: model.section >= 3
                                ? 'Buscar mensaje o referencia'
                                : 'Buscar',
                            prefixIcon: const Icon(Icons.search)),
                        onChanged: (v) => model.search = v,
                        onFieldSubmitted: (_) {
                          model.page = 1;
                          model.load();
                        },
                      )),
                if (model.section >= 2) ...[
                  OutlinedButton.icon(
                      onPressed: model.busy
                          ? null
                          : () async {
                              final dates = await showDateRangePicker(
                                  context: context,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                  initialDateRange: DateTimeRange(
                                      start: model.from, end: model.to));
                              if (dates != null) {
                                model.from = dates.start;
                                model.to = dates.end;
                                model.page = 1;
                                model.load();
                              }
                            },
                      icon: const Icon(Icons.date_range),
                      label: Text('${_date(model.from)} – ${_date(model.to)}')),
                  for (final days in [1, 7, 30])
                    TextButton(
                        onPressed: model.busy
                            ? null
                            : () {
                                final now = DateTime.now();
                                model.to = now;
                                model.from = DateTime(
                                    now.year, now.month, now.day - days + 1);
                                model.page = 1;
                                model.load();
                              },
                        child: Text(days == 1 ? 'Hoy' : '$days días')),
                ],
                if (model.section == 2) ...[
                  SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                          initialValue: model.transactionKind,
                          decoration:
                              const InputDecoration(labelText: 'Mostrar'),
                          items: const [
                            DropdownMenuItem(
                                value: 'sales', child: Text('Ventas')),
                            DropdownMenuItem(
                                value: 'payments', child: Text('Cobros'))
                          ],
                          onChanged: model.busy
                              ? null
                              : (v) {
                                  model.transactionKind = v!;
                                  model.page = 1;
                                  model.load();
                                })),
                  SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<String>(
                          initialValue: model.status,
                          decoration: const InputDecoration(
                              labelText: 'Estado de venta'),
                          items: [
                            const DropdownMenuItem<String>(
                                value: null, child: Text('Todos')),
                            for (final s in [
                              'Abierta',
                              'EnPedido',
                              'PedidoEnviado',
                              'ConCambios',
                              'Finalizada',
                              'Cancelada'
                            ])
                              DropdownMenuItem(value: s, child: Text(s))
                          ],
                          onChanged: model.busy
                              ? null
                              : (v) {
                                  model.status = v;
                                  model.page = 1;
                                  model.load();
                                })),
                ],
                if (model.section == 3)
                  SizedBox(
                      width: 180,
                      child: DropdownButtonFormField<bool>(
                          initialValue: model.resolved,
                          decoration: const InputDecoration(
                              labelText: 'Estado del error'),
                          items: const [
                            DropdownMenuItem<bool>(
                                value: null, child: Text('Todos')),
                            DropdownMenuItem(
                                value: false, child: Text('Pendientes')),
                            DropdownMenuItem(
                                value: true, child: Text('Resueltos'))
                          ],
                          onChanged: model.busy
                              ? null
                              : (v) {
                                  model.resolved = v;
                                  model.page = 1;
                                  model.load();
                                })),
              ]),
        ]),
      );
}

class _TransactionSummary extends StatelessWidget {
  final SystemAdminProvider model;
  const _TransactionSummary({required this.model});
  @override
  Widget build(BuildContext context) {
    final peak = model.daily.fold<double>(
        1,
        (p, d) => (d['amount'] as num).toDouble() > p
            ? (d['amount'] as num).toDouble()
            : p);
    return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                '${model.transactionKind == 'sales' ? 'Total de ventas finalizadas' : 'Total de cobros registrados'}: ${_money(model.amount)}',
                style: Theme.of(context).textTheme.titleMedium),
            if (model.daily.isNotEmpty)
              SizedBox(
                  height: 104,
                  child: ListView(scrollDirection: Axis.horizontal, children: [
                    for (final day in model.daily)
                      Tooltip(
                          message:
                              '${_date(DateTime.parse(day['date'] as String))}: ${_money(day['amount'] as num)} · ${day['count']} operaciones',
                          child: SizedBox(
                              width: 54,
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    Container(
                                        width: 26,
                                        height: (day['amount'] as num)
                                                    .toDouble()
                                                    .clamp(0, peak) /
                                                peak *
                                                64 +
                                            2,
                                        decoration: BoxDecoration(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary,
                                            borderRadius:
                                                BorderRadius.circular(4))),
                                    const SizedBox(height: 6),
                                    Text(
                                        _date(
                                            DateTime.parse(
                                                day['date'] as String),
                                            year: false),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall),
                                  ]))),
                  ])),
          ]),
        ));
  }
}

class _ResultCard extends StatelessWidget {
  final SystemAdminProvider model;
  final Map<String, dynamic> row;
  const _ResultCard({required this.model, required this.row});
  @override
  Widget build(BuildContext context) {
    if (model.section == 0) {
      return Card(
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${row['nombre']} · ${row['activa'] == true ? 'Activa' : 'Desactivada'}',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(
                        '${row['branches']} sucursales · ${row['users']} usuarios${row['cuit'] == null ? '' : ' · CUIT ${row['cuit']}'}'),
                    Wrap(spacing: 8, children: [
                      TextButton.icon(
                          onPressed: () => _editCompany(context, model, row),
                          icon: const Icon(Icons.edit_outlined),
                          label: const Text('Editar empresa')),
                      TextButton(
                          onPressed: () => _run(context, () async {
                                await model.selectCompany(row);
                                if (context.mounted) {
                                  await showDialog<void>(
                                      context: context,
                                      builder: (_) =>
                                          _BranchesDialog(model: model));
                                }
                              }, success: false),
                          child: const Text('Sucursales')),
                      TextButton(
                          onPressed: () => _run(context,
                              () => model.selectCompany(row, openSection: 1),
                              success: false),
                          child: const Text('Usuarios')),
                      TextButton(
                          onPressed: () => _run(context,
                              () => model.selectCompany(row, openSection: 2),
                              success: false),
                          child: const Text('Transacciones')),
                    ]),
                  ])));
    }
    if (model.section == 1) {
      return Card(
          child: ListTile(
        title: Text('${row['nombre']} ${row['apellido']}'),
        subtitle: Text(
            '${row['email']}\n${row['rolNombre']} · ${row['sucursalNombre']} · ${row['activo'] == true ? 'Activo' : 'Desactivado'}'),
        isThreeLine: true,
        trailing: IconButton(
            tooltip: 'Modificar usuario',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editUser(context, model, row)),
      ));
    }
    if (model.section == 2) {
      return Card(
          child: ListTile(
        title: Text(
            '${row['isRefund'] == true ? 'Devolución · ' : ''}Venta #${row['numero']} · ${_money(row['amount'] as num)}'),
        subtitle: Text(
            '${row['company']} · ${row['branch']}\n${_dateTime(row['date'])} · ${row['status']}${row['paymentTypeName'] == null ? '' : ' · ${row['paymentTypeName']}'}${row['paid'] == null ? '' : ' · Cobrado: ${_money(row['paid'] as num)}'}'),
        isThreeLine: true,
        onTap: () => _transactionDetail(
            context, model, (row['saleId'] ?? row['id']) as int),
      ));
    }
    return Card(
        child: ListTile(
      leading: Icon(model.section == 4
          ? Icons.history
          : row['resolved'] == true
              ? Icons.check_circle_outline
              : Icons.error_outline),
      title: Text(row['message'] as String),
      subtitle: Text(
          '${_dateTime(row['date'])} · ${row['source']}\n${row['path'] ?? ''}${row['traceId'] == null ? '' : ' · Ref. ${row['traceId']}'}'),
      isThreeLine: true,
      onTap: () => _eventDetail(context, model, row),
    ));
  }
}

class _CompanyPicker extends StatefulWidget {
  final SystemAdminProvider model;
  const _CompanyPicker({required this.model});
  @override
  State<_CompanyPicker> createState() => _CompanyPickerState();
}

class _CompanyPickerState extends State<_CompanyPicker> {
  final _search = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  int _page = 1, _total = 0, _generation = 0;
  bool _busy = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.model.request('GET', 'companies',
          query: {'search': _search.text, 'page': '$_page', 'pageSize': '30'});
      if (mounted && generation == _generation) {
        setState(() {
          _rows = (result['items'] as List).cast<Map<String, dynamic>>();
          _total = result['total'] as int;
        });
      }
    } catch (e) {
      if (mounted && generation == _generation) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Elegir empresa'),
          content: SizedBox(
              width: 520,
              height: 420,
              child: Column(children: [
                TextField(
                    controller: _search,
                    decoration: const InputDecoration(
                        labelText: 'Buscar empresa',
                        prefixIcon: Icon(Icons.search)),
                    onSubmitted: (_) {
                      _page = 1;
                      _load();
                    }),
                if (_busy) const LinearProgressIndicator(),
                if (_error != null) Text(_error!),
                Expanded(
                    child: ListView(children: [
                  for (final row in _rows)
                    ListTile(
                        title: Text(row['nombre'] as String),
                        subtitle: Text(
                            row['activa'] == true ? 'Activa' : 'Desactivada'),
                        onTap: () => Navigator.pop(context, row))
                ])),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  Text('Página $_page'),
                  IconButton(
                      onPressed: _busy || _page == 1
                          ? null
                          : () {
                              _page--;
                              _load();
                            },
                      icon: const Icon(Icons.chevron_left)),
                  IconButton(
                      onPressed: _busy || _page * 30 >= _total
                          ? null
                          : () {
                              _page++;
                              _load();
                            },
                      icon: const Icon(Icons.chevron_right)),
                ]),
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'))
          ]);
}

class _BranchesDialog extends StatefulWidget {
  final SystemAdminProvider model;
  const _BranchesDialog({required this.model});
  @override
  State<_BranchesDialog> createState() => _BranchesDialogState();
}

class _BranchesDialogState extends State<_BranchesDialog> {
  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Sucursales · ${widget.model.companies.first['nombre']}'),
        content: SizedBox(
            width: 560,
            height: 380,
            child: ListView(children: [
              for (final row in widget.model.branches)
                ListTile(
                    title: Text(row['nombre'] as String),
                    subtitle: Text(
                        '${row['direccion'] ?? ''} · ${row['activa'] == true ? 'Activa' : 'Desactivada'}'),
                    trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _edit(row))),
              if (widget.model.branches.isEmpty)
                const Text('Esta empresa todavía no tiene sucursales.'),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
          FilledButton.icon(
              onPressed: () => _edit(),
              icon: const Icon(Icons.add),
              label: const Text('Nueva sucursal'))
        ],
      );
  Future<void> _edit([Map<String, dynamic>? row]) async {
    final values = await _form(
        context,
        row == null ? 'Nueva sucursal' : 'Editar sucursal',
        const [
          _Field('nombre', 'Nombre', required: true),
          _Field('direccion', 'Dirección', maxLength: 300),
          _Field('telefono', 'Teléfono'),
        ],
        initial: row,
        activeKey: 'activa');
    if (values == null || !mounted) return;
    await _run(
        context,
        () => widget.model.save(
            'companies/${widget.model.companyId}/branches${row == null ? '' : '/${row['id']}'}',
            values,
            create: row == null));
    if (mounted) setState(() {});
  }
}

Future<void> _editCompany(BuildContext context, SystemAdminProvider model,
    [Map<String, dynamic>? row]) async {
  final values = await _form(
      context,
      row == null ? 'Nueva empresa' : 'Editar empresa',
      const [
        _Field('nombre', 'Nombre', required: true),
        _Field('cuit', 'CUIT'),
        _Field('email', 'Correo'),
        _Field('telefono', 'Teléfono'),
      ],
      initial: row,
      activeKey: 'activa');
  if (values == null || !context.mounted) return;
  await _run(
      context,
      () => model.save('companies${row == null ? '' : '/${row['id']}'}', values,
          create: row == null));
}

Future<void> _editUser(BuildContext context, SystemAdminProvider model,
    [Map<String, dynamic>? row]) async {
  if (model.branches.isEmpty) {
    _notice(context, 'Primero creá una sucursal para esta empresa.');
    return;
  }
  final values = await _form(
      context,
      row == null ? 'Nuevo usuario' : 'Editar usuario',
      [
        const _Field('nombre', 'Nombre', required: true),
        const _Field('apellido', 'Apellido', required: true),
        const _Field('email', 'Correo de acceso', required: true),
        _Field(
            'password',
            row == null
                ? 'Contraseña (mínimo 6 caracteres)'
                : 'Contraseña nueva (vacío para conservar)',
            password: true,
            required: row == null,
            minLength: 6),
      ],
      initial: row,
      activeKey: 'activo',
      choices: {
        'idRol': ('Tipo de usuario', model.roles),
        'idSucursal': ('Sucursal', model.branches),
      });
  if (values == null || !context.mounted) return;
  await _run(
      context,
      () => model.save(
          'companies/${model.companyId}/users${row == null ? '' : '/${row['id']}'}',
          {
            ...values,
            'idSectorAsignado': row?['idSectorAsignado'],
            'mesasExcluidasIds': row?['mesasExcluidasIds'] ?? [],
          },
          create: row == null));
}

Future<void> _eventDetail(BuildContext context, SystemAdminProvider model,
    Map<String, dynamic> row) async {
  final description =
      '${_dateTime(row['date'])}\n${row['message']}\nOrigen: ${row['source']}\nEmpresa: ${row['companyId'] ?? 'Sistema'} · Sucursal: ${row['branchId'] ?? '—'} · Usuario: ${row['userId'] ?? '—'}\n${row['method'] ?? ''} ${row['path'] ?? ''}\nReferencia: ${row['traceId'] ?? row['id']}\n\n${row['detail'] ?? ''}';
  if (model.section == 4) {
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Detalle de auditoría'),
              content: SizedBox(
                  width: 760,
                  child: SingleChildScrollView(
                      child: SelectableText(description))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cerrar'))
              ],
            ));
    return;
  }
  final values = await _form(
      context,
      'Detalle del error',
      const [
        _Field('note', 'Nota de seguimiento o solución',
            maxLength: 2000, lines: 3),
      ],
      initial: row,
      description: description,
      submitLabel:
          row['resolved'] == true ? 'Reabrir error' : 'Marcar resuelto');
  if (values == null || !context.mounted) return;
  await _run(
      context,
      () => model.save('events/${row['id']}/resolution',
          {'resolved': row['resolved'] != true, 'note': values['note']}));
}

Future<void> _transactionDetail(
    BuildContext context, SystemAdminProvider model, int id) async {
  await _run(context, () async {
    final data =
        await model.request('GET', 'transactions/$id') as Map<String, dynamic>;
    if (!context.mounted) return;
    await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: Text('Venta #${data['numero']}'),
              content: SizedBox(
                  width: 640,
                  child: SingleChildScrollView(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                        Text(
                            '${data['company']} · ${data['branch']}\nEstado: ${data['estado']}\nApertura: ${_dateTime(data['fechaApertura'])}${data['fechaCierre'] == null ? '' : '\nCierre: ${_dateTime(data['fechaCierre'])}'}'),
                        const Divider(),
                        for (final item in data['items'] as List)
                          Padding(
                              padding: const EdgeInsets.symmetric(vertical: 5),
                              child: Text(
                                  '${item['quantity']} × ${item['productName']} · ${_money(item['unitPrice'] as num)} = ${_money(item['subtotal'] as num)}${item['comment'] == null ? '' : '\n${item['comment']}'}')),
                        const Divider(),
                        Text(
                            'Subtotal: ${_money(data['subtotal'] as num)}\nDescuento: ${_money(data['importeDescuento'] as num)}\nTotal: ${_money(data['total'] as num)}'),
                        const SizedBox(height: 12),
                        const Text('Cobros registrados'),
                        for (final payment in data['payments'] as List)
                          Text(
                              '${payment['paymentTypeName']} · ${_money(payment['amount'] as num)} · ${_dateTime(payment['fecha'])}'),
                        if (data['annulment'] is Map) ...[
                          const Divider(),
                          Text(
                              'Venta anulada · ${_dateTime(data['annulment']['date'])}'),
                          Text('Motivo: ${data['annulment']['reason']}'),
                          Text(
                              'Devuelto: ${_money(data['annulment']['refunded'] as num)} · Usuario ${data['annulment']['userId']}'),
                        ],
                      ]))),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Cerrar'))
              ],
            ));
  }, success: false);
}

class _Field {
  final String key, label;
  final bool password, required;
  final int minLength, maxLength, lines;
  const _Field(this.key, this.label,
      {this.password = false,
      this.required = false,
      this.minLength = 0,
      this.maxLength = 150,
      this.lines = 1});
}

Future<Map<String, dynamic>?> _form(
  BuildContext context,
  String title,
  List<_Field> fields, {
  Map<String, dynamic>? initial,
  String? activeKey,
  Map<String, (String, List<Map<String, dynamic>>)> choices = const {},
  String? description,
  String submitLabel = 'Guardar',
}) =>
    showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) => _EditorDialog(
              title: title,
              fields: fields,
              initial: initial,
              activeKey: activeKey,
              choices: choices,
              description: description,
              submitLabel: submitLabel,
            ));

class _EditorDialog extends StatefulWidget {
  final String title, submitLabel;
  final String? activeKey, description;
  final List<_Field> fields;
  final Map<String, dynamic>? initial;
  final Map<String, (String, List<Map<String, dynamic>>)> choices;
  const _EditorDialog(
      {required this.title,
      required this.fields,
      required this.choices,
      required this.submitLabel,
      this.initial,
      this.activeKey,
      this.description});
  @override
  State<_EditorDialog> createState() => _EditorDialogState();
}

class _EditorDialogState extends State<_EditorDialog> {
  final _key = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  late final Map<String, dynamic> _selected;
  late bool _active;
  @override
  void initState() {
    super.initState();
    _controllers = {
      for (final field in widget.fields)
        field.key: TextEditingController(
            text: widget.initial?[field.key]?.toString() ?? '')
    };
    _selected = {
      for (final choice in widget.choices.entries)
        choice.key: widget.initial?[choice.key] ?? choice.value.$2.first['id']
    };
    _active = widget.initial?[widget.activeKey] as bool? ?? true;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
            width: widget.description == null ? 500 : 760,
            child: SingleChildScrollView(
                child: Form(
                    key: _key,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.description != null) ...[
                          SelectableText(widget.description!),
                          const SizedBox(height: 20)
                        ],
                        for (final field in widget.fields)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: TextFormField(
                                controller: _controllers[field.key],
                                obscureText: field.password,
                                minLines: field.lines,
                                maxLines: field.lines,
                                maxLength:
                                    field.password ? 72 : field.maxLength,
                                decoration:
                                    InputDecoration(labelText: field.label),
                                validator: (value) {
                                  final v = value ?? '';
                                  if (field.required && v.trim().isEmpty) {
                                    return 'Este dato es obligatorio.';
                                  }
                                  if (v.isNotEmpty &&
                                      v.length < field.minLength) {
                                    return 'Usá al menos ${field.minLength} caracteres.';
                                  }
                                  if (field.key == 'email' &&
                                      v.isNotEmpty &&
                                      !v.contains('@')) {
                                    return 'Ingresá un correo válido.';
                                  }
                                  return null;
                                },
                              )),
                        for (final choice in widget.choices.entries)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: DropdownButtonFormField<int>(
                                initialValue: _selected[choice.key] as int?,
                                isExpanded: true,
                                decoration:
                                    InputDecoration(labelText: choice.value.$1),
                                items: [
                                  for (final option in choice.value.$2)
                                    DropdownMenuItem(
                                        value: option['id'] as int,
                                        child: Text(option['nombre'] as String))
                                ],
                                onChanged: (value) =>
                                    _selected[choice.key] = value,
                                validator: (v) =>
                                    v == null ? 'Elegí una opción.' : null,
                              )),
                        if (widget.activeKey != null) ...[
                          SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Habilitado'),
                              value: _active,
                              onChanged: (v) => setState(() => _active = v)),
                          const Text(
                              'Al deshabilitar se bloquea el acceso, incluso para las sesiones abiertas.'),
                        ],
                      ],
                    )))),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () {
                if (!_key.currentState!.validate()) return;
                Navigator.pop(context, {
                  for (final field in widget.fields)
                    field.key: _controllers[field.key]!.text,
                  ..._selected,
                  if (widget.activeKey != null) widget.activeKey!: _active
                });
              },
              child: Text(widget.submitLabel)),
        ],
      );
}

Future<void> _run(BuildContext context, Future<void> Function() action,
    {bool success = true}) async {
  try {
    await action();
    if (context.mounted && success) _notice(context, 'Cambios guardados.');
  } catch (e) {
    if (context.mounted) {
      _notice(context, e.toString().replaceFirst('Exception: ', ''));
    }
  }
}

void _notice(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
String _money(num value) =>
    '\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
String _date(DateTime value, {bool year = true}) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}${year ? '/${value.year}' : ''}';
String _dateTime(dynamic value) {
  final date = DateTime.parse(value as String).toLocal();
  return '${_date(date)} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
