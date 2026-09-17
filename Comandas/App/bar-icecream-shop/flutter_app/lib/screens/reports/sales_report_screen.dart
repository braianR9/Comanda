import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_report_provider.dart';
import '../../providers/sector_provider.dart';

class SalesReportScreen extends StatefulWidget {
  final bool embedded;
  const SalesReportScreen({super.key, this.embedded = false});
  @override
  State<SalesReportScreen> createState() => _SalesReportScreenState();
}

class _SalesReportScreenState extends State<SalesReportScreen> {
  DateTime dateFrom = DateTime.now().subtract(const Duration(days: 1));
  DateTime dateTo = DateTime.now();
  TimeOfDay timeFrom = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay timeTo = const TimeOfDay(hour: 23, minute: 59);
  bool useTimeRange = false;
  bool showMoreFilters = false;
  String? rubroId;
  String? subRubroId;
  int? sectorId;
  final orderNumberController = TextEditingController();
  bool exporting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    orderNumberController.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final session = context.read<AuthProvider>().session!;
    await Future.wait([
      context
          .read<ProductProvider>()
          .load(session.idEmpresa, token: session.token),
      context.read<SectorProvider>().load(token: session.token),
    ]);
    await _reload();
  }

  Future<void> _reload() {
    final token = context.read<AuthProvider>().session!.token;
    return context.read<SalesReportProvider>().load(
          token,
          from: dateFrom,
          to: dateTo,
          useTimeRange: useTimeRange,
          timeFrom: _timeParam(timeFrom),
          timeTo: _timeParam(timeTo),
          rubroId: rubroId == null ? null : int.tryParse(rubroId!),
          subRubroId: subRubroId == null ? null : int.tryParse(subRubroId!),
          sectorId: sectorId,
          orderNumber: int.tryParse(orderNumberController.text.trim()),
        );
  }

  String _timeParam(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _export() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final token = context.read<AuthProvider>().session!.token;
      final bytes = await context.read<SalesReportProvider>().exportXlsx(
            token,
            from: dateFrom,
            to: dateTo,
            useTimeRange: useTimeRange,
            timeFrom: _timeParam(timeFrom),
            timeTo: _timeParam(timeTo),
            rubroId: rubroId == null ? null : int.tryParse(rubroId!),
            subRubroId: subRubroId == null ? null : int.tryParse(subRubroId!),
            sectorId: sectorId,
            orderNumber: int.tryParse(orderNumberController.text.trim()),
          );
      if (kIsWeb) {
        throw Exception(
            'La exportación todavía no está disponible en la versión web.');
      }
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Guardar listado de ventas',
        fileName: 'listado-ventas.xlsx',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (path == null || !mounted) return;
      await File(path).writeAsBytes(bytes);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Listado exportado en $path')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SalesReportProvider>();
    final groups = context.watch<ProductProvider>().groups;
    final rubros = groups.where((g) => !g.isSubgroup).toList();
    final subRubros =
        groups.where((g) => g.isSubgroup && g.parentId == rubroId).toList();
    final sectors = context.watch<SectorProvider>().sectors;
    final result = provider.result;

    final content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Detalle de productos vendidos por pedido',
                      style: GoogleFonts.poppins(
                          color: const Color(0xFF2D2260),
                          fontSize: 22,
                          fontWeight: FontWeight.w800)),
                  const Text('Estadísticas · Ventas · Listado de ventas',
                      style: TextStyle(color: Color(0xFF6B6589))),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: exporting ? null : _export,
              icon: exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_download_outlined),
              label: const Text('Exportar'),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _DatePickerField(
                    label: 'Desde',
                    value: dateFrom,
                    onPick: (v) => setState(() => dateFrom = v)),
                _DatePickerField(
                    label: 'Hasta',
                    value: dateTo,
                    onPick: (v) => setState(() => dateTo = v)),
                _TimePickerField(
                    label: 'Hora desde',
                    value: timeFrom,
                    onPick: (v) => setState(() => timeFrom = v)),
                _TimePickerField(
                    label: 'Hora hasta',
                    value: timeTo,
                    onPick: (v) => setState(() => timeTo = v)),
                FilterChip(
                  label: const Text('Rango horario'),
                  selected: useTimeRange,
                  onSelected: (v) => setState(() => useTimeRange = v),
                ),
                TextButton.icon(
                  onPressed: () =>
                      setState(() => showMoreFilters = !showMoreFilters),
                  icon: Icon(showMoreFilters
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded),
                  label: const Text('Más filtros'),
                ),
                FilledButton.icon(
                  onPressed: () => _reload(),
                  icon: const Icon(Icons.filter_alt_rounded),
                  label: const Text('Filtrar'),
                ),
              ]),
          if (showMoreFilters) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  value: rubroId,
                  decoration: const InputDecoration(labelText: 'Rubro'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    for (final r in rubros)
                      DropdownMenuItem(value: r.id, child: Text(r.name)),
                  ],
                  onChanged: (v) => setState(() {
                    rubroId = v;
                    subRubroId = null;
                  }),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String?>(
                  value: subRubroId,
                  decoration: const InputDecoration(labelText: 'Subrubro'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    for (final s in subRubros)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: rubroId == null
                      ? null
                      : (v) => setState(() => subRubroId = v),
                ),
              ),
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<int?>(
                  value: sectorId,
                  decoration: const InputDecoration(labelText: 'Sector'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Todos')),
                    for (final s in sectors)
                      DropdownMenuItem(value: s.id, child: Text(s.name)),
                  ],
                  onChanged: (v) => setState(() => sectorId = v),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  controller: orderNumberController,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _reload(),
                  decoration: const InputDecoration(
                      labelText: 'Número de pedido',
                      prefixIcon: Icon(Icons.receipt_long_rounded)),
                ),
              ),
            ]),
          ],
          const SizedBox(height: 16),
          Row(children: [
            Text('Cantidad: ${_qty(result.totalQuantity)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 24),
            Text('Total: \$${result.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(width: 24),
            Text('Total real: \$${result.totalRealAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          Expanded(
            child: provider.loading
                ? const Center(child: CircularProgressIndicator())
                : provider.error != null
                    ? Center(child: Text(provider.error!))
                    : result.items.isEmpty
                        ? const Center(
                            child: Text('No hay ventas para mostrar.'))
                        : Card(
                            margin: EdgeInsets.zero,
                            elevation: 0,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: const BorderSide(color: Color(0xFFE7E3F4)),
                            ),
                            child: Scrollbar(
                              thumbVisibility: true,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: SizedBox(
                                  width: 1600,
                                  child: ListView(
                                    children: [
                                      DataTable(
                                        headingRowColor:
                                            MaterialStateProperty.all(
                                                const Color(0xFFF0F0F2)),
                                        headingRowHeight: 44,
                                        dataRowMinHeight: 44,
                                        dataRowMaxHeight: 52,
                                        columnSpacing: 18,
                                        columns: const [
                                          DataColumn(label: Text('Fecha')),
                                          DataColumn(
                                              label: Text('N° de pedido')),
                                          DataColumn(label: Text('Código')),
                                          DataColumn(label: Text('Nombre')),
                                          DataColumn(label: Text('Cantidad')),
                                          DataColumn(label: Text('Total')),
                                          DataColumn(label: Text('Total real')),
                                          DataColumn(label: Text('Rubro')),
                                          DataColumn(label: Text('Subrubro')),
                                          DataColumn(
                                              label: Text('Tipo de pedido')),
                                          DataColumn(label: Text('Sector')),
                                        ],
                                        rows: result.items
                                            .map((line) => DataRow(cells: [
                                                  DataCell(Text(
                                                      _dateTime(line.date))),
                                                  DataCell(Text(
                                                      '${line.orderNumber}')),
                                                  DataCell(Text(
                                                      '${line.productCode}')),
                                                  DataCell(SizedBox(
                                                      width: 160,
                                                      child: Text(
                                                          line.productName,
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis))),
                                                  DataCell(Text(
                                                      _qty(line.quantity))),
                                                  DataCell(Text(
                                                      '\$${line.total.toStringAsFixed(2)}')),
                                                  DataCell(Text(
                                                      '\$${line.realAmount.toStringAsFixed(2)}')),
                                                  DataCell(
                                                      Text(line.rubroName)),
                                                  DataCell(Text(
                                                      line.subRubroName ?? '')),
                                                  DataCell(
                                                      Text(line.orderType)),
                                                  DataCell(Text(
                                                      line.sectorName ?? '')),
                                                ]))
                                            .toList(),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
          ),
        ]),
      ),
    );
    return widget.embedded
        ? ColoredBox(color: const Color(0xFFF5F5F8), child: content)
        : Scaffold(backgroundColor: const Color(0xFFF5F5F8), body: content);
  }

  String _qty(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(3);

  String _dateTime(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _DatePickerField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onPick;
  const _DatePickerField(
      {required this.label, required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 160,
        child: InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: value,
              firstDate: DateTime(2020),
              lastDate: DateTime.now().add(const Duration(days: 1)),
            );
            if (picked != null) onPick(picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.calendar_month_rounded),
            ),
            child: Text(
                '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}'),
          ),
        ),
      );
}

class _TimePickerField extends StatelessWidget {
  final String label;
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onPick;
  const _TimePickerField(
      {required this.label, required this.value, required this.onPick});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 130,
        child: InkWell(
          onTap: () async {
            final picked =
                await showTimePicker(context: context, initialTime: value);
            if (picked != null) onPick(picked);
          },
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              prefixIcon: const Icon(Icons.access_time_rounded),
            ),
            child: Text(
                '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}'),
          ),
        ),
      );
}
