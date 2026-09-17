import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../models/product.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/stock_movement_provider.dart';

class StockMovementsScreen extends StatefulWidget {
  final bool embedded;
  const StockMovementsScreen({super.key, this.embedded = false});
  @override
  State<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

class _StockMovementsScreenState extends State<StockMovementsScreen> {
  int? productId;
  String? type;
  final saleNumber = TextEditingController();
  DateTime? dateFrom;
  DateTime? dateTo;

  @override
  void dispose() {
    saleNumber.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final session = context.read<AuthProvider>().session!;
      context
          .read<ProductProvider>()
          .load(session.idEmpresa, token: session.token);
      context.read<StockMovementProvider>().load(session.token);
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<StockMovementProvider>();
    final products = context.watch<ProductProvider>().products;
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
                          Text('Movimientos de stock',
                              style: GoogleFonts.poppins(
                                  color: const Color(0xFF2D2260),
                                  fontSize: 25,
                                  fontWeight: FontWeight.w800)),
                          const Text('Ingresos y salidas de mercadería.',
                              style: TextStyle(color: Color(0xFF6B6589))),
                        ])),
                    FilledButton.icon(
                        onPressed: () => _add(products),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Nuevo movimiento'))
                  ]),
                  const SizedBox(height: 16),
                  LayoutBuilder(builder: (context, constraints) {
                    final fieldWidth = constraints.maxWidth >= 1100
                        ? (constraints.maxWidth - 48) / 5
                        : constraints.maxWidth >= 650
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth;
                    return Wrap(spacing: 12, runSpacing: 12, children: [
                      SizedBox(
                        width: fieldWidth,
                        child: DropdownButtonFormField<int?>(
                            isExpanded: true,
                            value: productId,
                            decoration:
                                const InputDecoration(labelText: 'Producto'),
                            items: [
                              const DropdownMenuItem(
                                  value: null, child: Text('Todos')),
                              ...products
                                  .where((p) => int.tryParse(p.id) != null)
                                  .map((p) => DropdownMenuItem(
                                      value: int.parse(p.id),
                                      child: Text(p.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis)))
                            ],
                            onChanged: (v) => setState(() => productId = v)),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: DropdownButtonFormField<String?>(
                            value: type,
                            decoration:
                                const InputDecoration(labelText: 'Tipo'),
                            items: const [
                              DropdownMenuItem(
                                  value: null, child: Text('Todos')),
                              DropdownMenuItem(
                                  value: 'Ingreso', child: Text('Ingreso')),
                              DropdownMenuItem(
                                  value: 'Egreso', child: Text('Egreso'))
                            ],
                            onChanged: (v) => setState(() => type = v)),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: TextField(
                          controller: saleNumber,
                          keyboardType: TextInputType.number,
                          onSubmitted: (_) => _reload(),
                          decoration: const InputDecoration(
                            labelText: 'Número de pedido',
                            prefixIcon: Icon(Icons.receipt_long_rounded),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: _DateFilter(
                          label: 'Fecha desde',
                          value: dateFrom,
                          onTap: () => _pickDate(from: true),
                        ),
                      ),
                      SizedBox(
                        width: fieldWidth,
                        child: _DateFilter(
                          label: 'Fecha hasta',
                          value: dateTo,
                          onTap: () => _pickDate(from: false),
                        ),
                      ),
                      FilledButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.search_rounded),
                        label: const Text('Buscar'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.filter_alt_off_rounded),
                        label: const Text('Limpiar'),
                      ),
                    ]);
                  }),
                  const SizedBox(height: 14),
                  Expanded(
                      child: provider.loading
                          ? const Center(child: CircularProgressIndicator())
                          : provider.error != null
                              ? Center(child: Text(provider.error!))
                              : provider.movements.isEmpty
                                  ? const Center(
                                      child: Text(
                                          'No hay movimientos para mostrar.'))
                                  : Card(
                                      margin: EdgeInsets.zero,
                                      elevation: 0,
                                      clipBehavior: Clip.antiAlias,
                                      child: ListView.separated(
                                          itemCount: provider.movements.length,
                                          separatorBuilder: (_, __) =>
                                              const Divider(height: 1),
                                          itemBuilder: (_, i) {
                                            final m = provider.movements[i];
                                            final positive = m.type
                                                .trim()
                                                .toLowerCase()
                                                .startsWith('ingres');
                                            return ListTile(
                                                leading: CircleAvatar(
                                                    backgroundColor: positive
                                                        ? const Color(
                                                            0xFFE8F5E9)
                                                        : const Color(
                                                            0xFFFFEBEE),
                                                    child: Icon(
                                                        positive
                                                            ? Icons.add_rounded
                                                            : Icons
                                                                .remove_rounded,
                                                        color: positive
                                                            ? Colors.green
                                                            : Colors.red)),
                                                title: Text(m.productName,
                                                    style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700)),
                                                subtitle: Text(
                                                    '${_date(m.date)}${m.saleNumber == null ? '' : ' · Pedido N.º ${m.saleNumber}'} · ${m.type}${m.note.isEmpty ? '' : ' · ${m.note}'}'),
                                                trailing: Column(
                                                    mainAxisAlignment:
                                                        MainAxisAlignment
                                                            .center,
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment.end,
                                                    children: [
                                                      Text(
                                                          '${positive ? '+' : '-'}${m.quantity}',
                                                          style: TextStyle(
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w800,
                                                              color: positive
                                                                  ? Colors.green
                                                                  : Colors
                                                                      .red)),
                                                      Text(
                                                          '${m.previousStock} → ${m.newStock}',
                                                          style:
                                                              const TextStyle(
                                                                  fontSize: 12))
                                                    ]));
                                          }))),
                ])));
    return widget.embedded
        ? ColoredBox(color: const Color(0xFFF5F5F8), child: content)
        : Scaffold(backgroundColor: const Color(0xFFF5F5F8), body: content);
  }

  void _reload() {
    final token = context.read<AuthProvider>().session!.token;
    final parsedSaleNumber = int.tryParse(saleNumber.text.trim());
    context.read<StockMovementProvider>().load(token,
        productId: productId,
        type: type,
        saleNumber: parsedSaleNumber,
        dateFrom: dateFrom,
        dateTo: dateTo);
  }

  Future<void> _pickDate({required bool from}) async {
    final selected = await showDatePicker(
        context: context,
        initialDate: (from ? dateFrom : dateTo) ?? DateTime.now(),
        firstDate: DateTime(2020),
        lastDate: DateTime.now());
    if (selected == null || !mounted) return;
    setState(() {
      if (from) {
        dateFrom = selected;
        if (dateTo != null && dateTo!.isBefore(selected)) {
          dateTo = selected;
        }
      } else {
        dateTo = selected;
        if (dateFrom != null && dateFrom!.isAfter(selected)) {
          dateFrom = selected;
        }
      }
    });
  }

  void _clearFilters() {
    setState(() {
      productId = null;
      type = null;
      saleNumber.clear();
      dateFrom = null;
      dateTo = null;
    });
    _reload();
  }

  Future<void> _add(List<Product> products) async {
    final value = await showDialog<_Adjustment>(
        context: context,
        builder: (_) => _AdjustmentDialog(products: products));
    if (value == null || !mounted) return;
    try {
      await context.read<StockMovementProvider>().add(
          productId: value.productId,
          type: value.type,
          quantity: value.quantity,
          note: value.note);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _DateFilter extends StatelessWidget {
  final String label;
  final DateTime? value;
  final VoidCallback onTap;

  const _DateFilter({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: const Icon(Icons.calendar_month_rounded),
            suffixIcon: value == null
                ? null
                : IconButton(
                    tooltip: 'Quitar fecha',
                    onPressed: onTap,
                    icon: const Icon(Icons.edit_calendar_outlined),
                  ),
          ),
          child: Text(value == null
              ? 'Todas'
              : '${value!.day.toString().padLeft(2, '0')}/${value!.month.toString().padLeft(2, '0')}/${value!.year}'),
        ),
      );
}

class _Adjustment {
  final int productId;
  final String type, note;
  final double quantity;
  const _Adjustment(this.productId, this.type, this.quantity, this.note);
}

class _AdjustmentDialog extends StatefulWidget {
  final List<Product> products;
  const _AdjustmentDialog({required this.products});
  @override
  State<_AdjustmentDialog> createState() => _AdjustmentDialogState();
}

class _AdjustmentDialogState extends State<_AdjustmentDialog> {
  final key = GlobalKey<FormState>();
  int? productId;
  String type = 'Ingreso';
  final quantity = TextEditingController(), note = TextEditingController();
  @override
  void dispose() {
    quantity.dispose();
    note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Nuevo movimiento'),
          content: Form(
              key: key,
              child: SizedBox(
                  width: 480,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    DropdownButtonFormField<int>(
                        isExpanded: true,
                        value: productId,
                        autofocus: true,
                        decoration:
                            const InputDecoration(labelText: 'Producto'),
                        items: widget.products
                            .where((p) => int.tryParse(p.id) != null)
                            .map((p) => DropdownMenuItem(
                                value: int.parse(p.id),
                                child: Text(p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis)))
                            .toList(),
                        onChanged: (v) => setState(() => productId = v),
                        validator: (v) =>
                            v == null ? 'Seleccioná un producto.' : null),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: DropdownButtonFormField<String>(
                              value: type,
                              decoration:
                                  const InputDecoration(labelText: 'Tipo'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'Ingreso', child: Text('Ingreso')),
                                DropdownMenuItem(
                                    value: 'Egreso', child: Text('Egreso'))
                              ],
                              onChanged: (v) => setState(() => type = v!))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: TextFormField(
                              controller: quantity,
                              decoration:
                                  const InputDecoration(labelText: 'Cantidad'),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              validator: (v) {
                                final n = double.tryParse(
                                    (v ?? '').replaceAll(',', '.'));
                                return n == null || n <= 0
                                    ? 'Cantidad inválida.'
                                    : null;
                              }))
                    ]),
                    const SizedBox(height: 12),
                    TextField(
                        controller: note,
                        maxLines: 2,
                        decoration:
                            const InputDecoration(labelText: 'Nota (opcional)'))
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  if (!key.currentState!.validate()) return;
                  Navigator.pop(
                      context,
                      _Adjustment(
                          productId!,
                          type,
                          double.parse(quantity.text.replaceAll(',', '.')),
                          note.text.trim()));
                },
                child: const Text('Guardar'))
          ]);
}
