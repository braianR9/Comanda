import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/price_list.dart';
import '../../providers/price_list_provider.dart';
import '../../providers/product_provider.dart';

const priceRuleOperations = {
  'DisminuirPorcentaje': 'Descuento %',
  'AumentarPorcentaje': 'Aumento %',
  'DisminuirImporte': 'Descuento de importe',
  'AumentarImporte': 'Aumento de importe',
  'PrecioFijo': 'Precio fijo',
};
const priceRuleDays = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
String ruleTime(int? minute) => minute == null
    ? ''
    : '${(minute ~/ 60).toString().padLeft(2, '0')}:${(minute % 60).toString().padLeft(2, '0')}';
String ruleDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
String readableRuleDate(String date) =>
    date.split('T').first.split('-').reversed.join('/');

class PriceRulesScreen extends StatefulWidget {
  const PriceRulesScreen({super.key});
  @override
  State<PriceRulesScreen> createState() => _PriceRulesScreenState();
}

class _PriceRulesScreenState extends State<PriceRulesScreen> {
  int? _listId;
  List<Map<String, dynamic>> _rules = [];
  bool _loading = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _listId = context.read<PriceListProvider>().lists.firstOrNull?.id;
    _load();
  }

  Future<void> _load() async {
    final id = _listId;
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rules = await context.read<PriceListProvider>().rules(id);
      if (mounted && id == _listId) setState(() => _rules = rules);
    } catch (e) {
      if (mounted && id == _listId) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted && id == _listId) setState(() => _loading = false);
    }
  }

  Future<void> _edit([Map<String, dynamic>? rule]) async {
    if (_listId == null) return;
    final result = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) => PriceRuleEditor(listId: _listId!, rule: rule)));
    if (result == true && mounted) await _load();
  }

  String _scope(Map<String, dynamic> rule) {
    if (rule['idProducto'] != null) return 'Producto #${rule['idProducto']}';
    final groups = context.read<ProductProvider>().groups;
    final id = rule['idSubRubro'] ?? rule['idRubro'];
    return id == null
        ? 'Toda la lista'
        : groups
                .where((g) =>
                    g.id == '$id' &&
                    g.isSubgroup == (rule['idSubRubro'] != null))
                .firstOrNull
                ?.name ??
            'Grupo #$id';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Promociones y aumentos programados')),
        body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                      'Hora argentina (UTC−3). Se aplica una sola regla: mayor prioridad; en empate, producto, subrubro, rubro y toda la lista. Si aún empatan, gana la más antigua. Fuera de vigencia se usa el precio base.'),
                  const SizedBox(height: 16),
                  Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                            width: 280,
                            child: DropdownButtonFormField<int>(
                                value: _listId,
                                decoration: const InputDecoration(
                                    labelText: 'Lista de precios'),
                                items: [
                                  for (final l in context
                                      .watch<PriceListProvider>()
                                      .lists)
                                    DropdownMenuItem(
                                        value: l.id,
                                        child: Text(
                                            '${l.nombre}${l.activa ? '' : ' (inactiva)'}'))
                                ],
                                onChanged: (v) {
                                  setState(() => _listId = v);
                                  _load();
                                })),
                        FilledButton.icon(
                            onPressed: _listId == null ? null : () => _edit(),
                            icon: const Icon(Icons.add),
                            label: const Text('Nueva regla')),
                        OutlinedButton.icon(
                            onPressed: _listId == null
                                ? null
                                : () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => PriceSimulationScreen(
                                            listId: _listId!))),
                            icon: const Icon(Icons.calculate_outlined),
                            label: const Text('Consultar precio por fecha')),
                      ]),
                  const SizedBox(height: 16),
                  Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? Center(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                      Text(_error!),
                                      TextButton(
                                          onPressed: _load,
                                          child: const Text('Reintentar'))
                                    ]))
                              : _rules.isEmpty
                                  ? const Center(
                                      child: Text(
                                          'No hay reglas. Los productos usan el precio base de esta lista.'))
                                  : ListView.builder(
                                      itemCount: _rules.length,
                                      itemBuilder: (_, i) {
                                        final rule = _rules[i];
                                        final days = [
                                          for (var d = 0; d < 7; d++)
                                            if (((rule['diasSemana'] as int) &
                                                    (1 << d)) !=
                                                0)
                                              priceRuleDays[d]
                                        ].join(', ');
                                        final hours = rule['minutoDesde'] ==
                                                null
                                            ? 'Todo el día'
                                            : '${ruleTime(rule['minutoDesde'] as int)}–${ruleTime(rule['minutoHasta'] as int)}${(rule['minutoDesde'] as int) > (rule['minutoHasta'] as int) ? ' del día siguiente' : ''}';
                                        return Card(
                                            child: ListTile(
                                                onTap: () => _edit(rule),
                                                title: Text(
                                                    '${rule['nombre']} · ${priceRuleOperations[rule['operacion']]} ${rule['valor']}'),
                                                subtitle: Text(
                                                    '${_scope(rule)} · Prioridad ${rule['prioridad']}\n${readableRuleDate(rule['fechaDesde'] as String)} → ${rule['fechaHasta'] == null ? 'Sin fecha de fin' : readableRuleDate(rule['fechaHasta'] as String)}\n$days · $hours'),
                                                isThreeLine: true,
                                                trailing: Chip(
                                                    label: Text(
                                                        rule['activa'] == true
                                                            ? 'Habilitada'
                                                            : 'Desactivada'))));
                                      })),
                ])),
      );
}

Future<ProductPrice?> pickRuleProduct(BuildContext context, int listId) =>
    showDialog<ProductPrice>(
        context: context, builder: (_) => _RuleProductPicker(listId: listId));

class _RuleProductPicker extends StatefulWidget {
  final int listId;
  const _RuleProductPicker({required this.listId});
  @override
  State<_RuleProductPicker> createState() => _RuleProductPickerState();
}

class _RuleProductPickerState extends State<_RuleProductPicker> {
  final _search = TextEditingController();
  PagedProductPrices? _result;
  bool _loading = true;
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

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await context
          .read<PriceListProvider>()
          .getPrices(widget.listId, texto: _search.text, page: page);
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Elegir producto'),
          content: SizedBox(
              width: 500,
              height: 440,
              child: Column(children: [
                TextField(
                    controller: _search,
                    enabled: !_loading,
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                        labelText: 'Nombre o código',
                        suffixIcon: IconButton(
                            onPressed: _loading ? null : () => _load(),
                            icon: const Icon(Icons.search)))),
                Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _error != null
                            ? Center(child: Text(_error!))
                            : ListView(children: [
                                for (final p
                                    in _result?.items ?? <ProductPrice>[])
                                  ListTile(
                                      title: Text('${p.codigo} · ${p.nombre}'),
                                      onTap: () => Navigator.pop(context, p))
                              ])),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  IconButton(
                      onPressed: _loading || (_result?.page ?? 1) <= 1
                          ? null
                          : () => _load(page: _result!.page - 1),
                      icon: const Icon(Icons.chevron_left)),
                  Text(
                      '${_result?.page ?? 1} / ${(_result?.totalPages ?? 1).clamp(1, 2147483647)}'),
                  IconButton(
                      onPressed: _loading ||
                              (_result?.page ?? 1) >= (_result?.totalPages ?? 1)
                          ? null
                          : () => _load(page: _result!.page + 1),
                      icon: const Icon(Icons.chevron_right)),
                ])
              ])),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'))
          ]);
}

class PriceRuleEditor extends StatefulWidget {
  final int listId;
  final Map<String, dynamic>? rule;
  const PriceRuleEditor({super.key, required this.listId, this.rule});
  @override
  State<PriceRuleEditor> createState() => _PriceRuleEditorState();
}

class _PriceRuleEditorState extends State<PriceRuleEditor> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _name, _value, _priority;
  late DateTime _from;
  DateTime? _until;
  int _days = 127;
  int? _start, _end, _target;
  String _scope = 'Lista',
      _operation = 'DisminuirPorcentaje',
      _roundMode = 'Arriba';
  String? _productName;
  double _round = 0;
  bool _active = true, _saving = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    final r = widget.rule;
    _name = TextEditingController(text: r?['nombre'] as String? ?? '');
    _value = TextEditingController(text: r?['valor']?.toString() ?? '');
    _priority = TextEditingController(text: '${r?['prioridad'] ?? 0}');
    final argentinaNow =
        DateTime.now().toUtc().subtract(const Duration(hours: 3));
    _from = r == null
        ? DateTime(argentinaNow.year, argentinaNow.month, argentinaNow.day)
        : DateTime.parse(r['fechaDesde'] as String);
    _until = r?['fechaHasta'] == null
        ? null
        : DateTime.parse(r!['fechaHasta'] as String);
    _days = r?['diasSemana'] as int? ?? 127;
    _start = r?['minutoDesde'] as int?;
    _end = r?['minutoHasta'] as int?;
    _operation = r?['operacion'] as String? ?? _operation;
    _active = r?['activa'] as bool? ?? true;
    _round = (r?['redondeo'] as num?)?.toDouble() ?? 0;
    _roundMode = r?['modoRedondeo'] as String? ?? 'Arriba';
    for (final scope in ['Producto', 'SubRubro', 'Rubro']) {
      if (r?['id$scope'] != null) {
        _scope = scope;
        _target = r!['id$scope'] as int;
        break;
      }
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _value.dispose();
    _priority.dispose();
    super.dispose();
  }

  Future<void> _date(bool end) async {
    final picked = await showDatePicker(
        context: context,
        initialDate: end ? _until ?? _from : _from,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100));
    if (picked != null && mounted) {
      setState(() {
        if (end) {
          _until = picked;
        } else {
          _from = picked;
        }
      });
    }
  }

  Future<void> _time(bool end) async {
    final value = (end ? _end : _start) ?? (end ? 1200 : 1080);
    final picked = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: value ~/ 60, minute: value % 60));
    if (picked != null && mounted) {
      setState(() {
        if (end) {
          _end = picked.hour * 60 + picked.minute;
        } else {
          _start = picked.hour * 60 + picked.minute;
        }
      });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (_days == 0 ||
        (_until != null && _until!.isBefore(_from)) ||
        (_scope != 'Lista' && _target == null) ||
        (_start == null) != (_end == null) ||
        (_start != null && _start == _end)) {
      setState(() =>
          _error = 'Revisá el alcance, las fechas, los días y los horarios.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<PriceListProvider>().saveRule(
          widget.listId,
          {
            'nombre': _name.text.trim(),
            'activa': _active,
            'prioridad': int.parse(_priority.text),
            'idProducto': _scope == 'Producto' ? _target : null,
            'idRubro': _scope == 'Rubro' ? _target : null,
            'idSubRubro': _scope == 'SubRubro' ? _target : null,
            'fechaDesde': ruleDate(_from),
            'fechaHasta': _until == null ? null : ruleDate(_until!),
            'diasSemana': _days,
            'minutoDesde': _start,
            'minutoHasta': _end,
            'operacion': _operation,
            'valor': double.parse(_value.text.trim().replaceAll(',', '.')),
            'redondeo': _round,
            'modoRedondeo': _roundMode,
            'version': widget.rule?['version'] ?? 0,
          },
          id: widget.rule?['id'] as int?);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = context
        .watch<ProductProvider>()
        .groups
        .where((g) => g.isSubgroup == (_scope == 'SubRubro'))
        .toList();
    return PopScope(
        canPop: !_saving,
        child: Scaffold(
          appBar: AppBar(
              title: Text(widget.rule == null
                  ? 'Nueva regla de precio'
                  : 'Editar regla de precio')),
          body: Center(
              child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: AbsorbPointer(
                    absorbing: _saving,
                    child: Form(
                        key: _form,
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(20),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  TextFormField(
                                      controller: _name,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Nombre (ej. Happy hour de bebidas)'),
                                      maxLength: 150,
                                      validator: (v) =>
                                          v == null || v.trim().isEmpty
                                              ? 'Ingresá un nombre'
                                              : null),
                                  SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Regla habilitada'),
                                      value: _active,
                                      onChanged: (v) =>
                                          setState(() => _active = v)),
                                  DropdownButtonFormField<String>(
                                      value: _scope,
                                      decoration: const InputDecoration(
                                          labelText: 'Aplicar a'),
                                      items: const [
                                        DropdownMenuItem(
                                            value: 'Lista',
                                            child: Text('Toda la lista')),
                                        DropdownMenuItem(
                                            value: 'Producto',
                                            child: Text('Un producto')),
                                        DropdownMenuItem(
                                            value: 'Rubro',
                                            child: Text('Un rubro')),
                                        DropdownMenuItem(
                                            value: 'SubRubro',
                                            child: Text('Un subrubro'))
                                      ],
                                      onChanged: (v) => setState(() {
                                            _scope = v!;
                                            _target = null;
                                            _productName = null;
                                          })),
                                  if (_scope == 'Producto')
                                    OutlinedButton.icon(
                                        onPressed: () async {
                                          final p = await pickRuleProduct(
                                              context, widget.listId);
                                          if (p != null && mounted) {
                                            setState(() {
                                              _target = p.idProducto;
                                              _productName = p.nombre;
                                            });
                                          }
                                        },
                                        icon: const Icon(Icons.search),
                                        label: Text(_productName ??
                                            (_target == null
                                                ? 'Elegir producto'
                                                : 'Producto #$_target'))),
                                  if (_scope == 'Rubro' || _scope == 'SubRubro')
                                    DropdownButtonFormField<int>(
                                        key: ValueKey(_scope),
                                        value: groups
                                                .any((g) => g.id == '$_target')
                                            ? _target
                                            : null,
                                        decoration: const InputDecoration(
                                            labelText: 'Seleccionar grupo'),
                                        items: [
                                          for (final g in groups)
                                            DropdownMenuItem(
                                                value: int.parse(g.id),
                                                child: Text(g.name))
                                        ],
                                        onChanged: (v) =>
                                            setState(() => _target = v),
                                        validator: (v) => v == null
                                            ? 'Elegí un grupo'
                                            : null),
                                  const SizedBox(height: 16),
                                  Wrap(spacing: 12, runSpacing: 8, children: [
                                    OutlinedButton(
                                        onPressed: () => _date(false),
                                        child: Text(
                                            'Desde: ${readableRuleDate(ruleDate(_from))}')),
                                    OutlinedButton(
                                        onPressed: () => _date(true),
                                        child: Text(
                                            'Hasta: ${_until == null ? 'Sin fecha de fin' : readableRuleDate(ruleDate(_until!))}')),
                                    if (_until != null)
                                      TextButton(
                                          onPressed: () =>
                                              setState(() => _until = null),
                                          child: const Text('Quitar fin')),
                                  ]),
                                  const SizedBox(height: 12),
                                  const Text('Días de inicio de la promoción'),
                                  Wrap(spacing: 6, children: [
                                    for (var d = 0; d < 7; d++)
                                      FilterChip(
                                          label: Text(priceRuleDays[d]),
                                          selected: (_days & (1 << d)) != 0,
                                          onSelected: (v) => setState(() =>
                                              _days = v
                                                  ? _days | (1 << d)
                                                  : _days & ~(1 << d)))
                                  ]),
                                  SwitchListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: const Text('Todo el día'),
                                      value: _start == null,
                                      onChanged: (v) => setState(() {
                                            _start = v ? null : 1080;
                                            _end = v ? null : 1200;
                                          })),
                                  if (_start != null)
                                    Wrap(spacing: 12, children: [
                                      OutlinedButton(
                                          onPressed: () => _time(false),
                                          child: Text(
                                              'Inicio: ${ruleTime(_start)}')),
                                      OutlinedButton(
                                          onPressed: () => _time(true),
                                          child:
                                              Text('Fin: ${ruleTime(_end)}')),
                                    ]),
                                  const Text(
                                      'Hora argentina (UTC−3). El horario de fin no se incluye. Si cruza medianoche, los días y fechas corresponden al día de inicio; por ejemplo viernes 22:00 a sábado 02:00.'),
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<String>(
                                      value: _operation,
                                      decoration: const InputDecoration(
                                          labelText: 'Ajuste'),
                                      items: [
                                        for (final op
                                            in priceRuleOperations.entries)
                                          DropdownMenuItem(
                                              value: op.key,
                                              child: Text(op.value))
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _operation = v!)),
                                  TextFormField(
                                      controller: _value,
                                      decoration: InputDecoration(
                                          labelText:
                                              _operation.contains('Porcentaje')
                                                  ? 'Porcentaje'
                                                  : 'Importe',
                                          suffixText:
                                              _operation.contains('Porcentaje')
                                                  ? '%'
                                                  : null),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                              decimal: true),
                                      validator: (v) {
                                        final value = double.tryParse((v ?? '')
                                            .trim()
                                            .replaceAll(',', '.'));
                                        return value == null ||
                                                !value.isFinite ||
                                                value < 0 ||
                                                !RegExp(r'^\d{1,16}([,.]\d{1,2})?$')
                                                    .hasMatch(
                                                        (v ?? '').trim()) ||
                                                (_operation.contains(
                                                        'Porcentaje') &&
                                                    value > 100)
                                            ? 'Ingresá un valor válido (porcentaje: 0 a 100)'
                                            : null;
                                      }),
                                  DropdownButtonFormField<double>(
                                      value: _round,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Redondear a múltiplos de'),
                                      items: [
                                        for (final v in {
                                          0.0,
                                          10.0,
                                          50.0,
                                          100.0,
                                          500.0,
                                          1000.0,
                                          _round
                                        })
                                          DropdownMenuItem(
                                              value: v,
                                              child: Text(v == 0
                                                  ? 'Sin redondeo'
                                                  : '\$$v'))
                                      ],
                                      onChanged: (v) =>
                                          setState(() => _round = v!)),
                                  if (_round > 0)
                                    DropdownButtonFormField<String>(
                                        value: _roundMode,
                                        decoration: const InputDecoration(
                                            labelText: 'Dirección'),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'Arriba',
                                              child: Text('Hacia arriba')),
                                          DropdownMenuItem(
                                              value: 'Abajo',
                                              child: Text('Hacia abajo')),
                                          DropdownMenuItem(
                                              value: 'Cercano',
                                              child: Text('Al más cercano'))
                                        ],
                                        onChanged: (v) =>
                                            setState(() => _roundMode = v!)),
                                  TextFormField(
                                      controller: _priority,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                          labelText:
                                              'Prioridad (gana el número más alto)'),
                                      validator: (v) {
                                        final n = int.tryParse(v ?? '');
                                        return n == null || n < 0 || n > 10000
                                            ? 'Usá un número entre 0 y 10000'
                                            : null;
                                      }),
                                  const SizedBox(height: 12),
                                  const Text(
                                      'Se aplica sobre el precio base de esta lista y no se acumula con otras reglas. Los productos sin precio base no se habilitan para venta.'),
                                  if (_error != null)
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 12),
                                        child: Text(_error!,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error))),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                      onPressed: _saving ? null : _save,
                                      icon: const Icon(Icons.save_outlined),
                                      label: Text(_saving
                                          ? 'Guardando…'
                                          : 'Guardar regla')),
                                ]))),
                  ))),
        ));
  }
}

class PriceSimulationScreen extends StatefulWidget {
  final int listId;
  const PriceSimulationScreen({super.key, required this.listId});
  @override
  State<PriceSimulationScreen> createState() => _PriceSimulationScreenState();
}

class _PriceSimulationScreenState extends State<PriceSimulationScreen> {
  ProductPrice? _product;
  late DateTime _day;
  late TimeOfDay _time;
  Map<String, dynamic>? _quote;
  String? _error;
  bool _loading = false;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now().toUtc().subtract(const Duration(hours: 3));
    _day = DateTime(now.year, now.month, now.day);
    _time = TimeOfDay(hour: now.hour, minute: now.minute);
  }

  Future<void> _consult() async {
    if (_product == null) return;
    setState(() {
      _loading = true;
      _error = null;
      _quote = null;
    });
    try {
      final instant = DateTime.utc(
              _day.year, _day.month, _day.day, _time.hour, _time.minute)
          .add(const Duration(hours: 3));
      final quotes = await context.read<PriceListProvider>().quotePrices(
          [_product!.idProducto],
          listId: widget.listId, instant: instant);
      if (mounted) setState(() => _quote = quotes[_product!.idProducto]);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Consultar precio por fecha')),
      body: AbsorbPointer(
          absorbing: _loading,
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text(
                'Simulá el precio para una fecha y hora argentina. Esta consulta no modifica precios ni ventas.'),
            const SizedBox(height: 16),
            OutlinedButton(
                onPressed: () async {
                  final p = await pickRuleProduct(context, widget.listId);
                  if (p != null && mounted) {
                    setState(() {
                      _product = p;
                      _quote = null;
                    });
                  }
                },
                child: Text(_product?.nombre ?? 'Elegir producto')),
            OutlinedButton(
                onPressed: () async {
                  final d = await showDatePicker(
                      context: context,
                      initialDate: _day,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100));
                  if (d != null && mounted) {
                    setState(() {
                      _day = d;
                      _quote = null;
                    });
                  }
                },
                child: Text('Fecha: ${readableRuleDate(ruleDate(_day))}')),
            OutlinedButton(
                onPressed: () async {
                  final t = await showTimePicker(
                      context: context, initialTime: _time);
                  if (t != null && mounted) {
                    setState(() {
                      _time = t;
                      _quote = null;
                    });
                  }
                },
                child:
                    Text('Hora: ${ruleTime(_time.hour * 60 + _time.minute)}')),
            FilledButton(
                onPressed: _loading || _product == null ? null : _consult,
                child: Text(_loading ? 'Consultando…' : 'Consultar')),
            if (_error != null)
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_quote != null)
              Card(
                  child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Lista: ${_quote!['listaNombre']}'),
                            Text(
                                'Precio base: ${_quote!['precioBase'] == null ? 'Sin configurar' : '\$${_quote!['precioBase']}'}'),
                            Text(
                                'Regla aplicada: ${_quote!['reglaNombre'] ?? 'Precio base (ninguna regla vigente)'}'),
                            Text(
                                'Precio final: ${_quote!['precioFinal'] == null ? 'No disponible para venta' : '\$${_quote!['precioFinal']}'}',
                                style:
                                    Theme.of(context).textTheme.headlineSmall),
                          ]))),
          ])));
}
