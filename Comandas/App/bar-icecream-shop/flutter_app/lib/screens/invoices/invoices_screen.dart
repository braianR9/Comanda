import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/invoice.dart';
import '../../providers/auth_provider.dart';
import '../purchases/purchase_api.dart';
import 'invoice_dialogs.dart';

String _dateTime(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String _money(num value) => '\$${value.toStringAsFixed(2)}';

/// Comprobantes emitidos (con quién y cuándo) y ventas cobradas pendientes de facturar.
class InvoicesScreen extends StatelessWidget {
  const InvoicesScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final api = PurchaseApi(context.read<AuthProvider>().session!.token);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
            title: const Text('Comprobantes electrónicos'),
            bottom: const TabBar(tabs: [
              Tab(text: 'Comprobantes emitidos'),
              Tab(text: 'Ventas sin facturar'),
            ])),
        body: TabBarView(children: [
          _IssuedTab(api: api),
          _PendingTab(api: api),
        ]),
      ),
    );
  }
}

/// Lista paginada con carga, error y vacío comunes a ambas pestañas.
abstract class _PagedState<T extends StatefulWidget, R> extends State<T>
    with AutomaticKeepAliveClientMixin {
  List<R> rows = [];
  int page = 1, pages = 1;
  bool loading = true;
  String? error;
  PurchaseApi get api;
  String get path;
  String get empty;
  R parse(Map<String, dynamic> item);
  Widget table(BuildContext context);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load([int target = 1]) async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data =
          Map<String, dynamic>.from(await api.call('$path?page=$target'));
      if (!mounted) return;
      setState(() {
        page = data['page'] as int;
        pages = (data['totalPages'] as int).clamp(1, 1 << 30);
        rows = [
          for (final item in data['items'] as List)
            parse(Map<String, dynamic>.from(item))
        ];
      });
    } catch (e) {
      if (mounted) {
        setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (loading) return const Center(child: CircularProgressIndicator());
    if (error != null) {
      return Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(error!),
        TextButton(onPressed: load, child: const Text('Reintentar')),
      ]));
    }
    return Column(children: [
      Align(
          alignment: Alignment.centerRight,
          child: IconButton(
              onPressed: () => load(page),
              tooltip: 'Actualizar',
              icon: const Icon(Icons.refresh))),
      Expanded(
        child: rows.isEmpty
            ? Center(child: Text(empty))
            : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(child: table(context))),
      ),
      if (pages > 1)
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              onPressed: page > 1 ? () => load(page - 1) : null,
              icon: const Icon(Icons.chevron_left)),
          Text('Página $page de $pages'),
          IconButton(
              onPressed: page < pages ? () => load(page + 1) : null,
              icon: const Icon(Icons.chevron_right)),
        ]),
    ]);
  }
}

// ─── Comprobantes emitidos ─────────────────────────────────────────────────

class _Issued {
  final Invoice invoice;
  final int saleNumber;
  final bool canRetry;
  final String? annulledBy;
  final DateTime? annulledAt;
  final String? annulledWith;
  final String? annulmentReason;
  final int reprints;
  final String? lastReprintBy;
  final DateTime? lastReprintAt;
  const _Issued(this.invoice, this.saleNumber, this.canRetry, this.annulledBy,
      this.annulledAt, this.annulledWith, this.annulmentReason,
      {this.reprints = 0, this.lastReprintBy, this.lastReprintAt});
}

class _IssuedTab extends StatefulWidget {
  final PurchaseApi api;
  const _IssuedTab({required this.api});
  @override
  State<_IssuedTab> createState() => _IssuedTabState();
}

class _IssuedTabState extends _PagedState<_IssuedTab, _Issued> {
  @override
  PurchaseApi get api => widget.api;
  @override
  String get path => 'comprobantes';
  @override
  String get empty =>
      'Todavía no hay comprobantes. Se facturan al cobrar o desde "Ventas sin facturar".';

  @override
  _Issued parse(Map<String, dynamic> item) {
    final annulment = item['annulment'] as Map?;
    final reprints = item['reprints'] as Map?;
    return _Issued(
      Invoice.fromJson(Map<String, dynamic>.from(item['invoice'])),
      item['saleNumber'] as int,
      item['canRetry'] == true,
      annulment?['userName']?.toString(),
      DateTime.tryParse(annulment?['at']?.toString() ?? '')?.toLocal(),
      annulment?['number']?.toString(),
      annulment?['reason']?.toString(),
      reprints: (reprints?['count'] as num?)?.toInt() ?? 0,
      lastReprintBy: reprints?['lastUserName']?.toString(),
      lastReprintAt:
          DateTime.tryParse(reprints?['lastAt']?.toString() ?? '')?.toLocal(),
    );
  }

  Future<void> _reprint(Invoice invoice) async {
    try {
      await api.call('comprobantes/${invoice.id}/reimprimir', method: 'POST');
      if (mounted) {
        snack('${invoice.typeName} ${invoice.number} enviada a la impresora.');
      }
    } catch (e) {
      if (mounted) snack(e.toString().replaceFirst('Exception: ', ''));
    }
    load(page);
  }

  Future<void> _creditNote(Invoice invoice) async {
    final reason = await showDialog<String>(
        context: context, builder: (_) => _CreditNoteDialog(invoice: invoice));
    if (reason == null || !mounted) return;
    try {
      final data = await api.call('comprobantes/${invoice.id}/nota-credito',
          method: 'POST', body: {'reason': reason});
      final note = Invoice.fromJson(Map<String, dynamic>.from(data));
      if (mounted) {
        snack('${note.typeName} ${note.number} autorizada · CAE ${note.cae}');
      }
    } catch (e) {
      if (mounted) snack(e.toString().replaceFirst('Exception: ', ''));
    }
    load(page);
  }

  Future<void> _retry(_Issued row) async {
    await showDialog<void>(
        context: context,
        builder: (_) => InvoiceDialog(
            api: api,
            saleId: row.invoice.saleId,
            title: 'Facturar la venta N.º ${row.saleNumber}',
            message:
                row.invoice.messages.isEmpty ? null : row.invoice.messages));
    load(page);
  }

  Widget _status(_Issued row) {
    final x = row.invoice;
    final (color, label) = switch (x.status) {
      'Autorizado' when x.creditNoteId != null => (Colors.grey, 'Anulada'),
      'Autorizado' => (Colors.green, 'Autorizado'),
      'Procesando' => (Colors.orange, 'Sin confirmar'),
      _ => (Colors.red, 'Rechazado'),
    };
    return Tooltip(
      message: x.messages,
      child: Chip(
          label: Text(label, style: TextStyle(color: color.shade800)),
          backgroundColor: color.shade50,
          side: BorderSide.none,
          visualDensity: VisualDensity.compact),
    );
  }

  /// Quién emitió y cuándo; si la factura se anuló, también quién y cuándo.
  Widget _audit(_Issued row) {
    final x = row.invoice;
    final lines = [
      '${x.isCreditNote ? 'Anuló' : x.authorized ? 'Facturó' : 'Intentó'}: ${x.userName.isEmpty ? '—' : x.userName}',
      _dateTime(x.authorizedAt ?? x.createdAt),
      if (x.isCreditNote && x.reason.isNotEmpty) 'Motivo: ${x.reason}',
      if (row.annulledBy != null)
        'Anulada por ${row.annulledBy} · ${_dateTime(row.annulledAt!)}',
      if ((row.annulmentReason ?? '').isNotEmpty)
        'Motivo: ${row.annulmentReason}',
      if (row.reprints > 0)
        'Reimpresa ${row.reprints} ${row.reprints == 1 ? 'vez' : 'veces'} · última: ${row.lastReprintBy ?? '—'} ${row.lastReprintAt == null ? '' : _dateTime(row.lastReprintAt!)}',
    ];
    return Text(lines.join('\n'), style: const TextStyle(fontSize: 12));
  }

  @override
  Widget table(BuildContext context) => DataTable(
        dataRowMinHeight: 48,
        dataRowMaxHeight: 88,
        columns: const [
          DataColumn(label: Text('Comprobante')),
          DataColumn(label: Text('Venta')),
          DataColumn(label: Text('Receptor')),
          DataColumn(label: Text('Total'), numeric: true),
          DataColumn(label: Text('CAE')),
          DataColumn(label: Text('Estado')),
          DataColumn(label: Text('Usuario y fecha')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final row in rows)
            DataRow(cells: [
              DataCell(Text(
                  '${row.invoice.typeName} ${row.invoice.number}${row.invoice.testing ? ' (prueba)' : ''}')),
              DataCell(Text('N.º ${row.saleNumber}')),
              DataCell(Text(row.invoice.receiver)),
              DataCell(Text(_money(row.invoice.total))),
              DataCell(Text(row.invoice.cae ?? '—')),
              DataCell(_status(row)),
              DataCell(_audit(row)),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                if (row.invoice.authorized)
                  IconButton(
                      onPressed: () => _reprint(row.invoice),
                      tooltip: 'Reimprimir',
                      icon: const Icon(Icons.print_outlined)),
                if (row.invoice.canCreditNote)
                  TextButton(
                      onPressed: () => _creditNote(row.invoice),
                      child: const Text('Anular')),
                if (!row.invoice.authorized &&
                    !row.invoice.isCreditNote &&
                    row.canRetry)
                  TextButton(
                      onPressed: () => _retry(row),
                      child: const Text('Reintentar')),
              ])),
            ]),
        ],
      );
}

/// Confirma la anulación y exige el motivo, que queda en el historial.
class _CreditNoteDialog extends StatefulWidget {
  final Invoice invoice;
  const _CreditNoteDialog({required this.invoice});
  @override
  State<_CreditNoteDialog> createState() => _CreditNoteDialogState();
}

class _CreditNoteDialogState extends State<_CreditNoteDialog> {
  final _reason = TextEditingController();
  String? _error;
  static const _suggestions = [
    'Error en los datos del cliente',
    'Error en el importe',
    'Devolución',
    'Venta cancelada',
  ];

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  void _confirm() {
    final text = _reason.text.trim();
    if (text.length < 3) {
      setState(() => _error = 'Indicá el motivo de la anulación.');
      return;
    }
    Navigator.pop(context, text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title:
            Text('Anular ${widget.invoice.typeName} ${widget.invoice.number}'),
        content: SizedBox(
          width: 420,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    'Se emitirá una nota de crédito por ${_money(widget.invoice.total)} en AFIP. No se puede deshacer.'),
                const SizedBox(height: 16),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final s in _suggestions)
                    ActionChip(
                        label: Text(s),
                        onPressed: () => setState(() {
                              _reason.text = s;
                              _error = null;
                            })),
                ]),
                const SizedBox(height: 12),
                TextField(
                    controller: _reason,
                    maxLength: 500,
                    maxLines: 2,
                    autofocus: true,
                    decoration: InputDecoration(
                        labelText: 'Motivo (obligatorio)', errorText: _error)),
              ]),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: _confirm, child: const Text('Emitir nota de crédito')),
        ],
      );
}

// ─── Ventas sin facturar ───────────────────────────────────────────────────

class _Pending {
  final int saleId, saleNumber;
  final DateTime? closedAt;
  final double total;
  final String table, cashier;
  final String? lastStatus, lastMessages, lastUser;
  final DateTime? lastAt;
  const _Pending(
      this.saleId,
      this.saleNumber,
      this.closedAt,
      this.total,
      this.table,
      this.cashier,
      this.lastStatus,
      this.lastMessages,
      this.lastUser,
      this.lastAt);
}

class _PendingTab extends StatefulWidget {
  final PurchaseApi api;
  const _PendingTab({required this.api});
  @override
  State<_PendingTab> createState() => _PendingTabState();
}

class _PendingTabState extends _PagedState<_PendingTab, _Pending> {
  @override
  PurchaseApi get api => widget.api;
  @override
  String get path => 'facturacion/pendientes';
  @override
  String get empty => 'Todas las ventas cobradas están facturadas.';

  @override
  _Pending parse(Map<String, dynamic> item) {
    final last = item['lastAttempt'] as Map?;
    return _Pending(
      item['saleId'] as int,
      item['saleNumber'] as int,
      DateTime.tryParse(item['closedAt']?.toString() ?? '')?.toLocal(),
      (item['total'] as num).toDouble(),
      item['table']?.toString() ?? '',
      item['cashier']?.toString() ?? '',
      last?['status']?.toString(),
      last?['messages']?.toString(),
      last?['userName']?.toString(),
      DateTime.tryParse(last?['at']?.toString() ?? '')?.toLocal(),
    );
  }

  Future<void> _invoice(_Pending row) async {
    await showDialog<void>(
        context: context,
        builder: (_) => InvoiceDialog(
            api: api,
            saleId: row.saleId,
            title: 'Facturar la venta N.º ${row.saleNumber}',
            message: row.lastStatus == 'Rechazado' &&
                    (row.lastMessages ?? '').isNotEmpty
                ? row.lastMessages
                : null));
    load(page);
  }

  Future<void> _ticket(_Pending row) async {
    try {
      await api.call('sales/${row.saleId}/ticket', method: 'POST');
      if (mounted) {
        snack(
            'Ticket de la venta N.º ${row.saleNumber} enviado a la impresora.');
      }
    } catch (e) {
      if (mounted) snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  String _last(_Pending row) => switch (row.lastStatus) {
        null => 'Nunca se facturó',
        'Anulada' => 'Factura anulada',
        'Procesando' => 'Sin confirmar',
        _ => 'Rechazada',
      };

  @override
  Widget table(BuildContext context) => DataTable(
        dataRowMinHeight: 48,
        dataRowMaxHeight: 64,
        columns: const [
          DataColumn(label: Text('Venta')),
          DataColumn(label: Text('Cobrada')),
          DataColumn(label: Text('Mesa')),
          DataColumn(label: Text('Cobró')),
          DataColumn(label: Text('Total'), numeric: true),
          DataColumn(label: Text('Último intento')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final row in rows)
            DataRow(cells: [
              DataCell(Text('N.º ${row.saleNumber}')),
              DataCell(
                  Text(row.closedAt == null ? '—' : _dateTime(row.closedAt!))),
              DataCell(Text(row.table)),
              DataCell(Text(row.cashier)),
              DataCell(Text(_money(row.total))),
              DataCell(Tooltip(
                  message: row.lastMessages ?? '',
                  child: Text(
                      [
                        _last(row),
                        if (row.lastUser != null && row.lastAt != null)
                          '${row.lastUser} · ${_dateTime(row.lastAt!)}',
                      ].join('\n'),
                      style: const TextStyle(fontSize: 12)))),
              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    onPressed: () => _ticket(row),
                    tooltip: 'Imprimir ticket de pago (no fiscal)',
                    icon: const Icon(Icons.receipt_long_outlined)),
                row.total > 0
                    ? FilledButton.tonal(
                        onPressed: () => _invoice(row),
                        child: const Text('Facturar'))
                    : const Text('Sin importe'),
              ])),
            ]),
        ],
      );
}
