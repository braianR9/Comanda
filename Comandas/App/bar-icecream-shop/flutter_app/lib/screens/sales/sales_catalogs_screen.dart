import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/auth_provider.dart';
import '../../providers/sales_catalogs_provider.dart';

class SalesCatalogsScreen extends StatefulWidget {
  final bool embedded;
  const SalesCatalogsScreen({super.key, this.embedded = false});
  @override
  State<SalesCatalogsScreen> createState() => _SalesCatalogsScreenState();
}

class _SalesCatalogsScreenState extends State<SalesCatalogsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)
      ..addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final token = context.read<AuthProvider>().session!.token;
      context.read<SalesCatalogsProvider>().load(token);
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SalesCatalogsProvider>();
    final content = SafeArea(
        child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Descuentos y tipos de pago',
                    style: GoogleFonts.poppins(
                        color: const Color(0xFF2D2260),
                        fontSize: 25,
                        fontWeight: FontWeight.w800)),
                const Text('Configuración de beneficios y medios de cobro.',
                    style: TextStyle(color: Color(0xFF6B6589))),
              ])),
          FilledButton.icon(
              onPressed: provider.loading ? null : _add,
              icon: const Icon(Icons.add_rounded),
              label: Text(_tabs.index == 0
                  ? 'Agregar descuento'
                  : 'Agregar tipo de pago')),
        ]),
        const SizedBox(height: 18),
        Card(
            margin: EdgeInsets.zero,
            elevation: 0,
            child: TabBar(controller: _tabs, tabs: const [
              Tab(icon: Icon(Icons.discount_outlined), text: 'Descuentos'),
              Tab(icon: Icon(Icons.payments_outlined), text: 'Tipos de pago'),
            ])),
        const SizedBox(height: 14),
        Expanded(
            child: provider.loading
                ? const Center(child: CircularProgressIndicator())
                : provider.error != null
                    ? Center(child: Text(provider.error!))
                    : TabBarView(
                        controller: _tabs,
                        children: [_discounts(provider), _cards(provider)])),
      ]),
    ));
    return widget.embedded
        ? ColoredBox(color: const Color(0xFFF5F5F8), child: content)
        : Scaffold(backgroundColor: const Color(0xFFF5F5F8), body: content);
  }

  Widget _discounts(SalesCatalogsProvider provider) =>
      _CatalogList(empty: 'No hay descuentos configurados.', children: [
        for (final item in provider.discounts)
          _CatalogTile(
            icon: Icons.discount_outlined,
            name: item.name,
            detail:
                '${_discountType(item.type)} · ${item.value.toStringAsFixed(2)}'
                '${item.type.toLowerCase().contains('percent') || item.type.toLowerCase().contains('porc') ? '%' : ''}',
            description: item.description,
            active: item.active,
            onEdit: () => _editDiscount(item),
            onToggle: () =>
                _run(() => provider.setDiscountActive(item, !item.active)),
          )
      ]);

  Widget _cards(SalesCatalogsProvider provider) =>
      _CatalogList(empty: 'No hay tipos de pago configurados.', children: [
        for (final item in provider.cards)
          _CatalogTile(
            icon: Icons.credit_card_rounded,
            name: item.name,
            detail:
                '${_adjustment(item.adjustmentType)} · ${item.percentage.toStringAsFixed(2)}%',
            description: item.description,
            active: item.active,
            onEdit: () => _editCard(item),
            onToggle: () =>
                _run(() => provider.setCardActive(item, !item.active)),
          )
      ]);

  void _add() => _tabs.index == 0 ? _editDiscount() : _editCard();

  Future<void> _editDiscount([DiscountCatalog? current]) async {
    final value = await showDialog<DiscountCatalog>(
        context: context, builder: (_) => _DiscountForm(current: current));
    if (value != null) {
      await _run(
          () => context.read<SalesCatalogsProvider>().saveDiscount(value));
    }
  }

  Future<void> _editCard([CardCatalog? current]) async {
    final value = await showDialog<CardCatalog>(
        context: context, builder: (_) => _CardForm(current: current));
    if (value != null) {
      await _run(() => context.read<SalesCatalogsProvider>().saveCard(value));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }

  String _discountType(String value) =>
      value.toLowerCase().contains('percent') ||
              value.toLowerCase().contains('porc')
          ? 'Porcentaje'
          : 'Importe';
  String _adjustment(String value) =>
      value.toLowerCase().contains('surcharge') ||
              value.toLowerCase().contains('recargo')
          ? 'Recargo'
          : value.toLowerCase().contains('discount') ||
                  value.toLowerCase().contains('descuento')
              ? 'Descuento'
              : 'Sin ajuste';
}

class _CatalogList extends StatelessWidget {
  final String empty;
  final List<Widget> children;
  const _CatalogList({required this.empty, required this.children});
  @override
  Widget build(BuildContext context) => children.isEmpty
      ? Center(child: Text(empty))
      : ListView.separated(
          itemCount: children.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, index) => children[index]);
}

class _CatalogTile extends StatelessWidget {
  final IconData icon;
  final String name, detail, description;
  final bool active;
  final VoidCallback onEdit, onToggle;
  const _CatalogTile(
      {required this.icon,
      required this.name,
      required this.detail,
      required this.description,
      required this.active,
      required this.onEdit,
      required this.onToggle});
  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: const BorderSide(color: Color(0xFFDCD9E7))),
        child: ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: CircleAvatar(
                backgroundColor: const Color(0xFFEDE9FF),
                child: Icon(icon, color: const Color(0xFF6C5CE7))),
            title:
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Text(
                [detail, if (description.trim().isNotEmpty) description]
                    .join(' · '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Chip(
                  label: Text(active ? 'Activo' : 'Inactivo'),
                  backgroundColor: active
                      ? const Color(0xFFE8F5E9)
                      : const Color(0xFFEEEEEE)),
              IconButton(
                  onPressed: onEdit,
                  tooltip: 'Editar',
                  icon: const Icon(Icons.edit_outlined)),
              IconButton(
                  onPressed: onToggle,
                  tooltip: active ? 'Desactivar' : 'Activar',
                  icon: Icon(
                      active
                          ? Icons.toggle_on_rounded
                          : Icons.toggle_off_rounded,
                      color: active ? const Color(0xFF6DA544) : Colors.grey,
                      size: 32)),
            ])),
      );
}

class _DiscountForm extends StatefulWidget {
  final DiscountCatalog? current;
  const _DiscountForm({this.current});
  @override
  State<_DiscountForm> createState() => _DiscountFormState();
}

class _DiscountFormState extends State<_DiscountForm> {
  final key = GlobalKey<FormState>();
  late final TextEditingController name, description, value;
  late String type;
  @override
  void initState() {
    super.initState();
    final item = widget.current;
    name = TextEditingController(text: item?.name);
    description = TextEditingController(text: item?.description);
    value = TextEditingController(text: item == null ? '' : '${item.value}');
    final savedType = item?.type.toLowerCase() ?? '';
    type = savedType.contains('amount') || savedType.contains('importe')
        ? 'Importe'
        : 'Porcentaje';
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.current == null
              ? 'Agregar descuento'
              : 'Editar descuento'),
          content: Form(
              key: key,
              child: SizedBox(
                  width: 480,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                        controller: name,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Nombre'),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Ingresá el nombre.'
                            : null),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: description,
                        maxLines: 2,
                        decoration: const InputDecoration(
                            labelText: 'Descripción (opcional)')),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: DropdownButtonFormField<String>(
                              value: type,
                              decoration:
                                  const InputDecoration(labelText: 'Tipo'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'Porcentaje',
                                    child: Text('Porcentaje')),
                                DropdownMenuItem(
                                    value: 'Importe', child: Text('Importe'))
                              ],
                              onChanged: (v) => setState(() => type = v!))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: TextFormField(
                              controller: value,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: InputDecoration(
                                  labelText: 'Valor',
                                  suffixText:
                                      type == 'Porcentaje' ? '%' : '\$'),
                              validator: (v) => double.tryParse(
                                          (v ?? '').replaceAll(',', '.')) ==
                                      null
                                  ? 'Valor inválido.'
                                  : null))
                    ]),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(onPressed: _save, child: const Text('Guardar'))
          ]);
  void _save() {
    if (!key.currentState!.validate()) return;
    final current = widget.current;
    Navigator.pop(
        context,
        DiscountCatalog(
            id: current?.id ?? 0,
            name: name.text.trim(),
            description: description.text.trim(),
            type: type,
            value: double.parse(value.text.replaceAll(',', '.')),
            active: current?.active ?? true,
            validFrom: current?.validFrom,
            validUntil: current?.validUntil));
  }
}

class _CardForm extends StatefulWidget {
  final CardCatalog? current;
  const _CardForm({this.current});
  @override
  State<_CardForm> createState() => _CardFormState();
}

class _CardFormState extends State<_CardForm> {
  final key = GlobalKey<FormState>();
  late final TextEditingController name, description, percentage;
  late String adjustment;
  @override
  void initState() {
    super.initState();
    final item = widget.current;
    name = TextEditingController(text: item?.name);
    description = TextEditingController(text: item?.description);
    percentage =
        TextEditingController(text: item == null ? '0' : '${item.percentage}');
    final savedAdjustment = item?.adjustmentType.toLowerCase() ?? '';
    adjustment = savedAdjustment.contains('surcharge') ||
            savedAdjustment.contains('recargo')
        ? 'Recargo'
        : savedAdjustment.contains('discount') ||
                savedAdjustment.contains('descuento')
            ? 'Descuento'
            : 'Sin ajuste';
  }

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    percentage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.current == null
              ? 'Agregar tipo de pago'
              : 'Editar tipo de pago'),
          content: Form(
              key: key,
              child: SizedBox(
                  width: 480,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(
                        controller: name,
                        autofocus: true,
                        decoration: const InputDecoration(labelText: 'Nombre'),
                        validator: (v) => v == null || v.trim().isEmpty
                            ? 'Ingresá el nombre.'
                            : null),
                    const SizedBox(height: 12),
                    TextFormField(
                        controller: description,
                        maxLines: 2,
                        decoration: const InputDecoration(
                            labelText: 'Descripción (opcional)')),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                          child: DropdownButtonFormField<String>(
                              value: adjustment,
                              decoration: const InputDecoration(
                                  labelText: 'Recargo o descuento'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'Sin ajuste',
                                    child: Text('Sin ajuste')),
                                DropdownMenuItem(
                                    value: 'Recargo', child: Text('Recargo')),
                                DropdownMenuItem(
                                    value: 'Descuento',
                                    child: Text('Descuento'))
                              ],
                              onChanged: (v) => setState(() {
                                    adjustment = v!;
                                    if (adjustment == 'Sin ajuste') {
                                      percentage.text = '0';
                                    }
                                  }))),
                      const SizedBox(width: 12),
                      Expanded(
                          child: TextFormField(
                              controller: percentage,
                              enabled: adjustment != 'Sin ajuste',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'Porcentaje', suffixText: '%'),
                              validator: (v) {
                                final n = double.tryParse(
                                    (v ?? '').replaceAll(',', '.'));
                                return n == null ||
                                        !n.isFinite ||
                                        n < 0 ||
                                        n > 100 ||
                                        (adjustment != 'Sin ajuste' && n == 0)
                                    ? 'Ingresá un porcentaje válido (mayor a 0 y hasta 100).'
                                    : null;
                              }))
                    ]),
                  ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(onPressed: _save, child: const Text('Guardar'))
          ]);
  void _save() {
    if (!key.currentState!.validate()) return;
    final current = widget.current;
    Navigator.pop(
        context,
        CardCatalog(
            id: current?.id ?? 0,
            name: name.text.trim(),
            description: description.text.trim(),
            adjustmentType: adjustment,
            percentage: double.parse(percentage.text.replaceAll(',', '.')),
            active: current?.active ?? true));
  }
}
