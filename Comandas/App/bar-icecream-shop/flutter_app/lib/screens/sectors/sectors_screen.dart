import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/restaurant_table.dart';
import '../../models/sector.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sector_provider.dart';

class SectorsScreen extends StatefulWidget {
  final bool embedded;

  const SectorsScreen({super.key, this.embedded = false});

  @override
  State<SectorsScreen> createState() => _SectorsScreenState();
}

class _SectorsScreenState extends State<SectorsScreen> {
  Sector? _layoutSector;
  final Map<int, List<_TableMock>> _tablesBySector = {};
  final Map<int, int> _visualSectorOrder = {};
  List<Sector> get _sectors => context.read<SectorProvider>().sectors;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final session = context.read<AuthProvider>().session!;
      final provider = context.read<SectorProvider>();
      await provider.load(token: session.token);
      if (!mounted) return;
      _syncApiTables(provider.tables);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SectorProvider>();
    _syncApiTables(provider.tables);
    if (_layoutSector != null) return _buildLayoutView(_layoutSector!);
    final body = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  Expanded(
                    child: Text(
                      'Sectores',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF2D2260),
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nuevo sector'),
                  ),
                ]),
                const SizedBox(height: 6),
                const Text(
                  'Organizá los sectores y el orden en que se muestran.',
                  style: TextStyle(color: Color(0xFF6B6589)),
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Card(
                    margin: EdgeInsets.zero,
                    elevation: 0,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFE1DDEF)),
                    ),
                    child: provider.loading
                        ? const Center(child: CircularProgressIndicator())
                        : provider.errorMessage != null
                            ? Center(child: Text(provider.errorMessage!))
                            : _sectors.isEmpty
                                ? const _EmptySectors()
                                : LayoutBuilder(
                                    builder: (context, constraints) {
                                    if (constraints.maxWidth < 680) {
                                      return _mobileList();
                                    }
                                    return _desktopTable();
                                  }),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return widget.embedded
        ? ColoredBox(color: const Color(0xFFF5F5F8), child: body)
        : Scaffold(backgroundColor: const Color(0xFFF5F5F8), body: body);
  }

  Widget _desktopTable() {
    final sectors = _orderedSectors;
    return Column(children: [
      const _SectorTableHeader(),
      Expanded(
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          itemCount: sectors.length,
          onReorder: _reorder,
          itemBuilder: (_, index) {
            final sector = sectors[index];
            return Material(
              key: ValueKey(sector.id),
              color: sector.active ? Colors.white : const Color(0xFFFAFAF8),
              child: InkWell(
                onTap: () => _openLayout(sector),
                child: Container(
                  constraints: const BoxConstraints(minHeight: 68),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: const BoxDecoration(
                    border:
                        Border(bottom: BorderSide(color: Color(0xFFEAE8EF))),
                  ),
                  child: Row(children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: Icon(Icons.drag_indicator_rounded,
                            color: Color(0xFFAAA5B8)),
                      ),
                    ),
                    SizedBox(
                      width: 54,
                      child: _OrderBadge(order: _orderFor(sector)),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(sector.name,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      flex: 5,
                      child: Text(sector.description,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 20),
                    SizedBox(
                        width: 82, child: _StatusChip(active: sector.active)),
                    SizedBox(
                      width: 52,
                      child: _SectorActions(
                        active: sector.active,
                        onEdit: () => _openForm(sector),
                        onToggle: () => _toggle(sector),
                      ),
                    ),
                  ]),
                ),
              ),
            );
          },
        ),
      ),
    ]);
  }

  Widget _mobileList() {
    final sectors = _orderedSectors;
    return ReorderableListView.builder(
      padding: const EdgeInsets.all(12),
      buildDefaultDragHandles: false,
      itemCount: sectors.length,
      onReorder: _reorder,
      itemBuilder: (_, index) {
        final sector = sectors[index];
        return Card(
          key: ValueKey(sector.id),
          margin: const EdgeInsets.only(bottom: 10),
          elevation: 0,
          color: sector.active ? Colors.white : const Color(0xFFF5F5F3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: const BorderSide(color: Color(0xFFE4E1EC)),
          ),
          child: ListTile(
            onTap: () => _openLayout(sector),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            leading: Row(mainAxisSize: MainAxisSize.min, children: [
              ReorderableDragStartListener(
                index: index,
                child: const Icon(Icons.drag_indicator_rounded,
                    color: Color(0xFFAAA5B8)),
              ),
            ]),
            title: Text(sector.name,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sector.description,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 7),
                Row(children: [
                  _OrderBadge(order: _orderFor(sector)),
                  const SizedBox(width: 8),
                  _StatusChip(active: sector.active),
                ]),
              ],
            ),
            trailing: _SectorActions(
              active: sector.active,
              onEdit: () => _openForm(sector),
              onToggle: () => _toggle(sector),
            ),
          ),
        );
      },
    );
  }

  List<Sector> get _orderedSectors => [..._sectors]..sort((a, b) {
      final byOrder = _orderFor(a).compareTo(_orderFor(b));
      return byOrder == 0 ? a.name.compareTo(b.name) : byOrder;
    });

  int _orderFor(Sector sector) =>
      _visualSectorOrder[sector.id] ??
      (sector.order > 0 ? sector.order : _sectors.indexOf(sector) + 1);

  Future<void> _openForm([Sector? sector]) async {
    final result = await showDialog<Sector>(
      context: context,
      builder: (_) => _SectorDialog(sector: sector),
    );
    if (result == null || !mounted) return;
    try {
      await context.read<SectorProvider>().saveSector(
            id: sector == null ? null : result.id,
            name: result.name,
            description: result.description,
            order: result.order,
          );
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  Future<void> _toggle(Sector sector) async {
    try {
      await context
          .read<SectorProvider>()
          .setSectorActive(sector, !sector.active);
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _reorder(int oldIndex, int newIndex) {
    final reordered = _orderedSectors;
    if (newIndex > oldIndex) newIndex--;
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);
    setState(() {
      for (var index = 0; index < reordered.length; index++) {
        _visualSectorOrder[reordered[index].id] = index + 1;
      }
    });
  }

  void _openLayout(Sector sector) {
    setState(() {
      _layoutSector = sector;
      _tablesBySector.putIfAbsent(sector.id, () => []);
    });
  }

  Widget _buildLayoutView(Sector sector) {
    final tables = _tablesBySector[sector.id]!;
    final content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
        child: Column(children: [
          Row(children: [
            IconButton(
              onPressed: () => setState(() {
                _layoutSector = null;
              }),
              tooltip: 'Volver a sectores',
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Distribución · ${sector.name}',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF2D2260),
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      )),
                  const Text('Arrastrá las mesas y tocá una para editarla.',
                      style: TextStyle(color: Color(0xFF6B6589))),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: _addTable,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Agregar mesa'),
            ),
          ]),
          const SizedBox(height: 16),
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFDFDFC),
                    borderRadius: BorderRadius.circular(24),
                    border:
                        Border.all(color: const Color(0xFFB9B9B4), width: 2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x12000000),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(builder: (context, constraints) {
                    return Stack(children: [
                      Positioned(
                        left: 18,
                        top: 14,
                        child: Text(sector.name.toUpperCase(),
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFB2B0B7),
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.4,
                            )),
                      ),
                      for (var index = 0; index < tables.length; index++)
                        Positioned(
                          left: tables[index].x *
                              (constraints.maxWidth -
                                  _floorTableSize(tables[index]).width),
                          top: tables[index].y *
                              (constraints.maxHeight -
                                  _floorTableSize(tables[index]).height),
                          child: GestureDetector(
                            onTap: () => _editTable(tables[index]),
                            onPanUpdate: (details) => _moveTable(
                              sector.id,
                              index,
                              details.delta,
                              constraints.biggest,
                              _floorTableSize(tables[index]),
                            ),
                            onPanEnd: (_) => _saveTablePosition(tables[index]),
                            child: _FloorTable(table: tables[index]),
                          ),
                        ),
                    ]);
                  }),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const _FloorLegend(),
        ]),
      ),
    );
    return widget.embedded
        ? ColoredBox(color: const Color(0xFFF5F5F8), child: content)
        : Scaffold(backgroundColor: const Color(0xFFF5F5F8), body: content);
  }

  void _moveTable(
      int sectorId, int index, Offset delta, Size canvas, Size tableSize) {
    final tables = _tablesBySector[sectorId]!;
    final table = tables[index];
    final usableWidth = canvas.width - tableSize.width;
    final usableHeight = canvas.height - tableSize.height;
    if (usableWidth <= 0 || usableHeight <= 0) return;
    setState(() {
      tables[index] = table.copyWith(
        x: (table.x + delta.dx / usableWidth).clamp(0.0, 1.0),
        y: (table.y + delta.dy / usableHeight).clamp(0.0, 1.0),
      );
    });
  }

  Future<void> _addTable() async {
    final tables = _tablesBySector[_layoutSector!.id]!;
    final nextNumber = tables.isEmpty
        ? 1
        : tables.map((table) => table.number).reduce((a, b) => a > b ? a : b) +
            1;
    final form = await showDialog<_TableFormValue>(
      context: context,
      builder: (_) => _TableDialog(suggestedNumber: nextNumber),
    );
    if (form == null || !mounted) return;
    try {
      final provider = context.read<SectorProvider>();
      for (var index = 0; index < form.quantity; index++) {
        final number = nextNumber + index;
        final name = form.quantity == 1
            ? form.name
            : _numberedTableName(form.name, number);
        final saved = await provider.addTable(
          sectorId: _layoutSector!.id,
          name: name,
          description: form.description,
          shape: form.shape,
          capacity: form.capacity,
          positionX: (.08 + (index % 6) * .15).clamp(0.0, .90),
          positionY: (.12 + (index ~/ 6) * .20).clamp(0.0, .90),
        );
        if (!tables.any((table) => table.id == saved.id)) {
          tables.add(_TableMock.fromApi(saved));
        }
      }
      if (!mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(form.quantity == 1
            ? 'Mesa creada correctamente.'
            : '${form.quantity} mesas creadas correctamente.'),
      ));
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  String _numberedTableName(String baseName, int number) {
    final cleanBase = baseName.trim().replaceFirst(RegExp(r'\s*\d+\s*$'), '');
    return '${cleanBase.isEmpty ? 'Mesa' : cleanBase} $number';
  }

  Future<void> _editTable(_TableMock table) async {
    final form = await showDialog<_TableFormValue>(
      context: context,
      builder: (_) => _TableDialog(
        suggestedNumber: table.number,
        initial: table,
      ),
    );
    if (form == null || !mounted) return;
    final provider = context.read<SectorProvider>();
    final sectorId = _layoutSector!.id;
    try {
      await provider.updateTable(RestaurantTable(
        id: table.id,
        number: table.number,
        name: form.name,
        description: form.description,
        sectorId: sectorId,
        status: table.status,
        shape: form.shape,
        capacity: form.capacity,
        active: table.active,
        positionX: table.x,
        positionY: table.y,
      ));
      if (form.active != table.active) {
        await provider.setTableActive(
          RestaurantTable(
            id: table.id,
            number: table.number,
            name: form.name,
            description: form.description,
            sectorId: sectorId,
            status: table.status,
            shape: form.shape,
            capacity: form.capacity,
            active: table.active,
            positionX: table.x,
            positionY: table.y,
          ),
          form.active,
        );
      }
      if (!mounted) return;
      final tables = _tablesBySector[_layoutSector!.id]!;
      final index = tables.indexWhere((item) => item.id == table.id);
      if (index != -1) {
        setState(() => tables[index] = table.copyWith(
              name: form.name,
              description: form.description,
              shape: form.shape,
              seats: form.capacity,
              active: form.active,
            ));
      }
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _syncApiTables(List<RestaurantTable> apiTables) {
    for (final table in apiTables) {
      final sectorTables =
          _tablesBySector.putIfAbsent(table.sectorId, () => []);
      if (!sectorTables.any((item) => item.id == table.id)) {
        sectorTables.add(_TableMock.fromApi(table));
      }
    }
  }

  Future<void> _saveTablePosition(_TableMock table) async {
    try {
      await context.read<SectorProvider>().updateTable(RestaurantTable(
            id: table.id,
            number: table.number,
            name: table.name,
            description: table.description,
            sectorId: _layoutSector!.id,
            status: table.status,
            shape: table.shape,
            capacity: table.seats,
            active: table.active,
            positionX: table.x,
            positionY: table.y,
          ));
    } catch (error) {
      if (mounted) _showError(error);
    }
  }

  void _showError(Object error) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error.toString().replaceFirst('Exception: ', '')),
    ));
  }
}

class _SectorTableHeader extends StatelessWidget {
  const _SectorTableHeader();

  @override
  Widget build(BuildContext context) => Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        color: const Color(0xFFF1F1EF),
        child: const Row(children: [
          SizedBox(width: 36),
          SizedBox(width: 54, child: Text('Orden')),
          Expanded(flex: 3, child: Text('Nombre')),
          SizedBox(width: 20),
          Expanded(flex: 5, child: Text('Descripción')),
          SizedBox(width: 20),
          SizedBox(width: 82, child: Text('Estado')),
          SizedBox(width: 52),
        ]),
      );
}

class _OrderBadge extends StatelessWidget {
  final int order;

  const _OrderBadge({required this.order});

  @override
  Widget build(BuildContext context) => Container(
        width: 34,
        padding: const EdgeInsets.symmetric(vertical: 5),
        decoration: BoxDecoration(
          color: const Color(0xFFF0EEF5),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: Text('$order',
            style: const TextStyle(
                color: Color(0xFF5E5876), fontWeight: FontWeight.w600)),
      );
}

class _TableDialog extends StatefulWidget {
  final int suggestedNumber;
  final _TableMock? initial;
  const _TableDialog({required this.suggestedNumber, this.initial});

  @override
  State<_TableDialog> createState() => _TableDialogState();
}

class _TableDialogState extends State<_TableDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _capacity;
  late final TextEditingController _quantity;
  late String _shape;
  late bool _active;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
        text: widget.initial?.name ?? 'Mesa ${widget.suggestedNumber}');
    _description =
        TextEditingController(text: widget.initial?.description ?? '');
    _capacity = TextEditingController(text: '${widget.initial?.seats ?? 4}');
    _quantity = TextEditingController(text: '1');
    _shape = _normalizedShape(widget.initial?.shape);
    _active = widget.initial?.active ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _capacity.dispose();
    _quantity.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: const Color(0xFFF5F5F3),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFD0D1CE)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(widget.initial == null ? 'Nueva mesa' : 'Editar mesa',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF45474A),
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 22),
                  TextFormField(
                    controller: _name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: _required,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _description,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Descripción (opcional)',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _shape,
                        decoration: const InputDecoration(labelText: 'Forma'),
                        items: const ['Circular', 'Cuadrada', 'Rectangular']
                            .map((value) => DropdownMenuItem(
                                value: value, child: Text(value)))
                            .toList(),
                        onChanged: (value) => setState(() => _shape = value!),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: TextFormField(
                        controller: _capacity,
                        keyboardType: TextInputType.number,
                        decoration:
                            const InputDecoration(labelText: 'Capacidad'),
                        validator: (value) {
                          final parsed = int.tryParse(value ?? '');
                          return parsed == null || parsed < 1
                              ? 'Ingresá una capacidad válida'
                              : null;
                        },
                      ),
                    ),
                  ]),
                  if (widget.initial == null) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _quantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Cantidad de mesas',
                        helperText:
                            'Se numerarán automáticamente desde el nombre indicado.',
                      ),
                      validator: (value) {
                        final parsed = int.tryParse(value ?? '');
                        return parsed == null || parsed < 1 || parsed > 100
                            ? 'Ingresá una cantidad entre 1 y 100'
                            : null;
                      },
                    ),
                  ],
                  if (widget.initial != null) ...[
                    const SizedBox(height: 14),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mesa activa'),
                      subtitle: Text(_active
                          ? 'Disponible para usar en ventas'
                          : 'No aparecerá para nuevos pedidos'),
                      value: _active,
                      onChanged: (value) => setState(() => _active = value),
                    ),
                  ],
                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_rounded),
                      label: Text(widget.initial == null
                          ? 'Guardar mesa'
                          : 'Guardar cambios'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio' : null;

  String _normalizedShape(String? value) {
    switch (value?.toLowerCase()) {
      case 'circular':
      case 'circle':
      case 'redonda':
        return 'Circular';
      case 'cuadrada':
      case 'square':
        return 'Cuadrada';
      case 'rectangular':
      case 'rectangle':
        return 'Rectangular';
      default:
        return 'Circular';
    }
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _TableFormValue(
        name: _name.text.trim(),
        description: _description.text.trim(),
        shape: _shape,
        capacity: int.parse(_capacity.text),
        active: _active,
        quantity: widget.initial == null ? int.parse(_quantity.text) : 1,
      ),
    );
  }
}

class _TableFormValue {
  final String name;
  final String description;
  final String shape;
  final int capacity;
  final bool active;
  final int quantity;
  const _TableFormValue({
    required this.name,
    required this.description,
    required this.shape,
    required this.capacity,
    required this.active,
    required this.quantity,
  });
}

class _SectorDialog extends StatefulWidget {
  final Sector? sector;

  const _SectorDialog({this.sector});

  @override
  State<_SectorDialog> createState() => _SectorDialogState();
}

class _SectorDialogState extends State<_SectorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _order;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.sector?.name ?? '');
    _description =
        TextEditingController(text: widget.sector?.description ?? '');
    _order = TextEditingController(text: '${widget.sector?.order ?? 1}');
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _order.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: const Color(0xFFF5F5F3),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFD0D1CE)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.sector == null ? 'Nuevo sector' : 'Editar sector',
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF45474A),
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                      )),
                  const SizedBox(height: 22),
                  TextFormField(
                    controller: _name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: _required,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                    validator: _required,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _order,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Orden'),
                    validator: (value) {
                      final parsed = int.tryParse(value ?? '');
                      return parsed == null || parsed < 0
                          ? 'Ingresá un número válido'
                          : null;
                    },
                  ),
                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Guardar'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio' : null;

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      Sector(
        id: widget.sector?.id ?? 0,
        name: _name.text.trim(),
        description: _description.text.trim(),
        order: int.parse(_order.text),
        active: widget.sector?.active ?? true,
      ),
    );
  }
}

class _SectorActions extends StatelessWidget {
  final bool active;
  final VoidCallback onEdit;
  final VoidCallback onToggle;

  const _SectorActions({
    required this.active,
    required this.onEdit,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        tooltip: 'Acciones',
        onSelected: (value) {
          if (value == 'edit') return onEdit();
          onToggle();
        },
        itemBuilder: (_) => [
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.edit_outlined),
              title: Text('Editar'),
            ),
          ),
          PopupMenuItem(
            value: 'toggle',
            child: ListTile(
              dense: true,
              leading: Icon(active
                  ? Icons.block_outlined
                  : Icons.check_circle_outline_rounded),
              title: Text(active ? 'Desactivar' : 'Activar'),
            ),
          ),
        ],
      );
}

class _StatusChip extends StatelessWidget {
  final bool active;

  const _StatusChip({required this.active});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFE8F5E9) : const Color(0xFFEEEEEC),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          active ? 'Activo' : 'Inactivo',
          style: TextStyle(
            color: active ? const Color(0xFF388E3C) : const Color(0xFF696B6E),
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

class _EmptySectors extends StatelessWidget {
  const _EmptySectors();

  @override
  Widget build(BuildContext context) => const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_module_outlined,
                size: 48, color: Color(0xFFAAA5BE)),
            SizedBox(height: 12),
            Text('Todavía no hay sectores.'),
          ],
        ),
      );
}

class _TableMock {
  final int id;
  final int number;
  final String name;
  final String description;
  final String shape;
  final double x;
  final double y;
  final int seats;
  final bool rectangular;
  final String status;
  final bool active;
  final int? joinedGroupId;

  const _TableMock({
    required this.id,
    required this.number,
    this.name = '',
    this.description = '',
    this.shape = 'Circular',
    required this.x,
    required this.y,
    required this.seats,
    this.rectangular = false,
    this.status = 'Libre',
    this.active = true,
    this.joinedGroupId,
  });

  factory _TableMock.fromApi(RestaurantTable table) => _TableMock(
        id: table.id,
        number: table.number,
        name: table.name,
        description: table.description,
        shape: table.shape,
        x: table.positionX.clamp(0.0, 1.0),
        y: table.positionY.clamp(0.0, 1.0),
        seats: table.capacity,
        rectangular: table.shape.toLowerCase() == 'rectangular',
        status: table.status,
        active: table.active,
      );

  _TableMock copyWith({
    double? x,
    double? y,
    String? name,
    String? description,
    String? shape,
    int? seats,
    bool? active,
    int? joinedGroupId,
  }) =>
      _TableMock(
        id: id,
        number: number,
        name: name ?? this.name,
        description: description ?? this.description,
        shape: shape ?? this.shape,
        x: x ?? this.x,
        y: y ?? this.y,
        seats: seats ?? this.seats,
        rectangular: (shape ?? this.shape).toLowerCase() == 'rectangular',
        status: status,
        active: active ?? this.active,
        joinedGroupId: joinedGroupId ?? this.joinedGroupId,
      );
}

Size _floorTableSize(_TableMock table) =>
    table.shape.toLowerCase() == 'rectangular'
        ? const Size(118, 80)
        : const Size(92, 92);

class _FloorTable extends StatelessWidget {
  final _TableMock table;

  const _FloorTable({required this.table});

  @override
  Widget build(BuildContext context) {
    final shape = table.shape.toLowerCase();
    final circular = shape == 'circular' || shape == 'redonda';
    final rectangular = shape == 'rectangular';
    return Opacity(
      opacity: table.active ? 1 : .48,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        width: rectangular ? 118 : 92,
        height: rectangular ? 80 : 92,
        decoration: BoxDecoration(
          color: table.active ? Colors.white : const Color(0xFFE4E4E1),
          shape: circular ? BoxShape.circle : BoxShape.rectangle,
          borderRadius:
              circular ? null : BorderRadius.circular(rectangular ? 16 : 10),
          border: Border.all(
            color: const Color(0xFFAAA7AE),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(
                color: Color(0x18000000), blurRadius: 8, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(table.name.isEmpty ? 'Mesa ${table.number}' : table.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF343238),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                )),
            const SizedBox(height: 2),
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.person_outline_rounded,
                  size: 13, color: Color(0xFF77737E)),
              Text('${table.seats}',
                  style:
                      const TextStyle(color: Color(0xFF77737E), fontSize: 11)),
            ]),
            const Icon(Icons.edit_outlined, size: 13, color: Color(0xFF8A8790)),
          ],
        ),
      ),
    );
  }
}

class _FloorLegend extends StatelessWidget {
  const _FloorLegend();

  @override
  Widget build(BuildContext context) => const Wrap(
        alignment: WrapAlignment.center,
        spacing: 20,
        runSpacing: 8,
        children: [
          _LegendItem(icon: Icons.drag_indicator_rounded, label: 'Arrastrar'),
          _LegendItem(icon: Icons.edit_outlined, label: 'Tocar para editar'),
        ],
      );
}

class _LegendItem extends StatelessWidget {
  final IconData icon;
  final String label;

  const _LegendItem({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 17, color: const Color(0xFF77737E)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(color: Color(0xFF6B6589))),
        ],
      );
}
