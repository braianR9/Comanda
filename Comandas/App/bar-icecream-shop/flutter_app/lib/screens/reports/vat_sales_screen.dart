import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

import '../../config/api_config.dart';
import '../../providers/auth_provider.dart';
import '../../theme/brand_colors.dart';
import '../../utils/api_response.dart';
import '../../utils/file_download.dart';

/// Renglón del Libro de IVA Ventas; las notas de crédito llegan en negativo.
class VatSalesLine {
  final DateTime date;
  final String voucher, customer, vatCondition;
  final int pointOfSale;
  final String? cuit;
  final double subtotal, vat105, vat21, vat27, total;
  final bool testing;
  const VatSalesLine(
      this.date,
      this.voucher,
      this.pointOfSale,
      this.customer,
      this.vatCondition,
      this.cuit,
      this.subtotal,
      this.vat105,
      this.vat21,
      this.vat27,
      this.total,
      this.testing);

  factory VatSalesLine.fromJson(Map<String, dynamic> j) => VatSalesLine(
        _wallClock(DateTime.parse(j['date'].toString())),
        j['voucher'] as String,
        (j['pointOfSale'] as num).toInt(),
        j['customer'] as String,
        j['vatCondition'] as String,
        j['cuit'] as String?,
        (j['subtotal'] as num).toDouble(),
        (j['vat105'] as num).toDouble(),
        (j['vat21'] as num).toDouble(),
        (j['vat27'] as num).toDouble(),
        (j['total'] as num).toDouble(),
        j['testing'] == true,
      );
}

/// Ventas · Libro de IVA Ventas, con exportación a Excel.
class VatSalesScreen extends StatefulWidget {
  final bool embedded;
  const VatSalesScreen({super.key, this.embedded = false});
  @override
  State<VatSalesScreen> createState() => _VatSalesScreenState();
}

class _VatSalesScreenState extends State<VatSalesScreen> {
  DateTime dateFrom = DateTime.now().subtract(const Duration(days: 1));
  DateTime dateTo = DateTime.now();
  TimeOfDay timeFrom = const TimeOfDay(hour: 0, minute: 0);
  TimeOfDay timeTo = const TimeOfDay(hour: 23, minute: 59);
  bool useTimeRange = false;
  bool loading = false, exporting = false;
  String? error;
  List<VatSalesLine> items = [];
  Map<String, dynamic> totals = const {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Uri _uri(String path) =>
      Uri.parse('${ApiConfig.baseUrl}$path').replace(queryParameters: {
        'from': _apiDate(dateFrom),
        'to': _apiDate(dateTo, endOfDay: true),
        'rangoHorario': '$useTimeRange',
        'horaDesde': _timeParam(timeFrom),
        'horaHasta': _timeParam(timeTo),
      });

  Map<String, String> get _headers => {
        ...ApiConfig.headers,
        'Authorization':
            'Bearer ${context.read<AuthProvider>().session!.token}',
      };

  String _apiDate(DateTime d, {bool endOfDay = false}) => DateTime(
          d.year,
          d.month,
          d.day,
          endOfDay ? 23 : 0,
          endOfDay ? 59 : 0,
          endOfDay ? 59 : 0,
          endOfDay ? 999 : 0)
      .toUtc()
      .toIso8601String();

  String _timeParam(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await http
          .get(_uri('/api/reports/iva-ventas'), headers: _headers)
          .timeout(ApiConfig.timeout);
      final body = decodeApiResponse(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(body['error']?.toString() ??
            'Error del servidor (${response.statusCode}).');
      }
      final data = body['data'] as Map<String, dynamic>? ?? const {};
      if (!mounted) return;
      setState(() {
        items = [
          for (final item in data['items'] as List? ?? const [])
            VatSalesLine.fromJson(Map<String, dynamic>.from(item))
        ];
        totals = Map<String, dynamic>.from(data['totals'] as Map? ?? {});
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _export() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final response = await http
          .get(_uri('/api/reports/iva-ventas/export'), headers: _headers)
          .timeout(ApiConfig.timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
            'No se pudo exportar el libro de IVA (${response.statusCode}).');
      }
      final saved = await saveExcelFile(
          'libro-iva-ventas.xlsx', response.bodyBytes,
          dialogTitle: 'Guardar libro de IVA ventas');
      if (saved == null || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Libro de IVA exportado: $saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  double _total(String key) => (totals[key] as num?)?.toDouble() ?? 0;

  @override
  Widget build(BuildContext context) {
    const bold = TextStyle(fontWeight: FontWeight.w700, fontSize: 13);
    final content = SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('Libro de IVA Ventas',
                  style: GoogleFonts.poppins(
                      color: Brand.ink,
                      fontSize: 22,
                      fontWeight: FontWeight.w800)),
            ),
            OutlinedButton.icon(
              onPressed: exporting || items.isEmpty ? null : _export,
              icon: exporting
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.file_download_outlined),
              label: const Text('Exportar a Excel'),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _DateField(
                    label: 'Desde',
                    value: dateFrom,
                    onPick: (v) => setState(() => dateFrom = v)),
                _DateField(
                    label: 'Hasta',
                    value: dateTo,
                    onPick: (v) => setState(() => dateTo = v)),
                _TimeField(
                    label: 'Hora desde',
                    value: timeFrom,
                    enabled: useTimeRange,
                    onPick: (v) => setState(() => timeFrom = v)),
                _TimeField(
                    label: 'Hora hasta',
                    value: timeTo,
                    enabled: useTimeRange,
                    onPick: (v) => setState(() => timeTo = v)),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Checkbox(
                      value: useTimeRange,
                      onChanged: (v) =>
                          setState(() => useTimeRange = v ?? false)),
                  GestureDetector(
                      onTap: () => setState(() => useTimeRange = !useTimeRange),
                      child: const Text('Rango horario')),
                ]),
                FilledButton.icon(
                  onPressed: loading ? null : _load,
                  icon: const Icon(Icons.filter_alt_rounded),
                  label: const Text('Filtrar'),
                ),
              ]),
          const SizedBox(height: 16),
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(child: Text(error!))
                    : items.isEmpty
                        ? const Center(
                            child: Text(
                                'No hay comprobantes autorizados en ese período.'))
                        : Card(
                            margin: EdgeInsets.zero,
                            elevation: 0,
                            clipBehavior: Clip.antiAlias,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(color: Brand.surface)),
                            child: LayoutBuilder(
                              builder: (context, constraints) =>
                                  SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth),
                                  child: SingleChildScrollView(
                                    child: DataTable(
                                      headingRowColor: WidgetStateProperty.all(
                                          const Color(0xFFF0F0F2)),
                                      columnSpacing: 16,
                                      horizontalMargin: 12,
                                      headingRowHeight: 40,
                                      dataRowMinHeight: 36,
                                      dataRowMaxHeight: 44,
                                      headingTextStyle: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.black87),
                                      dataTextStyle: const TextStyle(
                                          fontSize: 13, color: Colors.black87),
                                      columns: const [
                                        DataColumn(label: Text('Fecha')),
                                        DataColumn(label: Text('Comprobante')),
                                        DataColumn(
                                            label: Text('Punto de venta'),
                                            numeric: true),
                                        DataColumn(label: Text('Cliente')),
                                        DataColumn(
                                            label: Text('Condición IVA')),
                                        DataColumn(label: Text('CUIT')),
                                        DataColumn(
                                            label: Text('Subtotal'),
                                            numeric: true),
                                        DataColumn(
                                            label: Text('IVA 10,5 %'),
                                            numeric: true),
                                        DataColumn(
                                            label: Text('IVA 21%'),
                                            numeric: true),
                                        DataColumn(
                                            label: Text('IVA 27%'),
                                            numeric: true),
                                        DataColumn(
                                            label: Text('Total'),
                                            numeric: true),
                                      ],
                                      rows: [
                                        // Totales arriba, como en el libro de referencia.
                                        DataRow(
                                            color: WidgetStateProperty.all(
                                                const Color(0xFFF7F7F9)),
                                            cells: [
                                              for (var i = 0; i < 6; i++)
                                                const DataCell(Text('')),
                                              DataCell(Text(
                                                  _money(_total('subtotal')),
                                                  style: bold)),
                                              DataCell(Text(
                                                  _money(_total('vat105')),
                                                  style: bold)),
                                              DataCell(Text(
                                                  _money(_total('vat21')),
                                                  style: bold)),
                                              DataCell(Text(
                                                  _money(_total('vat27')),
                                                  style: bold)),
                                              DataCell(Text(
                                                  _money(_total('total')),
                                                  style: bold)),
                                            ]),
                                        for (final x in items)
                                          DataRow(cells: [
                                            DataCell(Text(_dateTime(x.date))),
                                            DataCell(Text(x.testing
                                                ? '${x.voucher} (prueba)'
                                                : x.voucher)),
                                            DataCell(Text('${x.pointOfSale}')),
                                            DataCell(Text(x.customer)),
                                            DataCell(Text(x.vatCondition)),
                                            DataCell(Text(x.cuit ?? '')),
                                            DataCell(Text(_money(x.subtotal))),
                                            DataCell(Text(_money(x.vat105))),
                                            DataCell(Text(_money(x.vat21))),
                                            DataCell(Text(_money(x.vat27))),
                                            DataCell(Text(_money(x.total))),
                                          ]),
                                      ],
                                    ),
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
}

/// La API ya manda la hora de Argentina (marcada como UTC): se muestra tal cual,
/// sin convertir a la zona del navegador.
DateTime _wallClock(DateTime d) =>
    DateTime(d.year, d.month, d.day, d.hour, d.minute, d.second);

/// Importe con formato argentino: $17.628,10.
String _money(double value) {
  final negative = value < 0;
  final parts = value.abs().toStringAsFixed(2).split('.');
  final digits = parts[0];
  final grouped = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) grouped.write('.');
    grouped.write(digits[i]);
  }
  return '${negative ? '-' : ''}\$$grouped,${parts[1]}';
}

String _dateTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

class _DateField extends StatelessWidget {
  final String label;
  final DateTime value;
  final ValueChanged<DateTime> onPick;
  const _DateField(
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
                prefixIcon: const Icon(Icons.calendar_month_rounded)),
            child: Text(
                '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}'),
          ),
        ),
      );
}

class _TimeField extends StatelessWidget {
  final String label;
  final TimeOfDay value;
  final bool enabled;
  final ValueChanged<TimeOfDay> onPick;
  const _TimeField(
      {required this.label,
      required this.value,
      required this.enabled,
      required this.onPick});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 130,
        child: InkWell(
          onTap: !enabled
              ? null
              : () async {
                  final picked = await showTimePicker(
                      context: context, initialTime: value);
                  if (picked != null) onPick(picked);
                },
          child: InputDecorator(
            decoration: InputDecoration(
                labelText: label,
                enabled: enabled,
                prefixIcon: const Icon(Icons.access_time_rounded)),
            child: Text(
                '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
                style: TextStyle(color: enabled ? null : Colors.grey)),
          ),
        ),
      );
}
