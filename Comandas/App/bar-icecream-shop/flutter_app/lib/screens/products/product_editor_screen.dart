import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../models/product_group.dart';
import '../../models/product_tax.dart';
import '../../providers/product_provider.dart';

class ProductEditorScreen extends StatefulWidget {
  final Product? product;
  final bool embedded;
  final ValueChanged<Product>? onSaved;
  final VoidCallback? onCancel;
  const ProductEditorScreen({
    super.key,
    this.product,
    this.embedded = false,
    this.onSaved,
    this.onCancel,
  });

  @override
  State<ProductEditorScreen> createState() => _ProductEditorScreenState();
}

class _ProductEditorScreenState extends State<ProductEditorScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController name,
      code,
      category,
      subcategory,
      cost,
      price,
      description;
  late final TextEditingController tax, currentStock, minimumStock, idealStock;
  int section = 0;
  String type = 'Producto simple';
  String? selectedTaxId;
  bool stockAlarm = false, minimumAlarm = false, checkOnSale = false;
  String stockUpdatesOn = 'Producto';
  String quantityOperation = 'Entero';
  bool delivery = true, salon = true, digitalMenu = true;
  Uint8List? productImage;
  final List<String> categories = [];
  final Map<String, List<String>> subcategoriesByCategory = {};

  Product get initial =>
      widget.product ??
      Product(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: '',
        category: '',
        price: 0,
      );

  @override
  void initState() {
    super.initState();
    final p = initial;
    name = TextEditingController(text: p.name);
    code = TextEditingController(text: p.code);
    category = TextEditingController(text: p.category);
    subcategory = TextEditingController(text: p.subcategory);
    cost = TextEditingController(text: p.cost.toStringAsFixed(2));
    price = TextEditingController(text: p.price.toStringAsFixed(2));
    description = TextEditingController(text: p.description);
    tax = TextEditingController(text: p.taxRate.toStringAsFixed(0));
    currentStock =
        TextEditingController(text: p.currentStock.toStringAsFixed(0));
    selectedTaxId = p.taxId;
    final availableTaxes = context.read<ProductProvider>().taxes;
    if (!availableTaxes.any((item) => item.id == selectedTaxId) &&
        availableTaxes.isNotEmpty) {
      final matchingRate =
          availableTaxes.where((item) => item.percentage == p.taxRate);
      final selected =
          matchingRate.isNotEmpty ? matchingRate.first : availableTaxes.first;
      selectedTaxId = selected.id;
      tax.text = selected.percentage.toString();
    }
    minimumStock =
        TextEditingController(text: p.minimumStock.toStringAsFixed(0));
    idealStock = TextEditingController(text: p.idealStock.toStringAsFixed(0));
    type = p.type;
    stockAlarm = p.stockAlarm;
    minimumAlarm = p.minimumStockAlarm;
    checkOnSale = p.checkStockOnSale;
    stockUpdatesOn = p.stockUpdatesOn;
    quantityOperation = p.quantityOperation;
    delivery = p.showDelivery;
    salon = p.showSalon;
    digitalMenu = p.showDigitalMenu;
    if (p.imageBase64 != null && p.imageBase64!.isNotEmpty) {
      try {
        productImage = base64Decode(p.imageBase64!);
      } catch (_) {}
    }
    if (p.category.isNotEmpty) categories.add(p.category);
    if (p.category.isNotEmpty && p.subcategory.isNotEmpty) {
      subcategoriesByCategory
          .putIfAbsent(p.category, () => [])
          .add(p.subcategory);
    }
    for (final product in context.read<ProductProvider>().products) {
      if (product.category.isNotEmpty &&
          !categories.contains(product.category)) {
        categories.add(product.category);
      }
      if (product.category.isNotEmpty && product.subcategory.isNotEmpty) {
        final children = subcategoriesByCategory.putIfAbsent(
            product.category, () => <String>[]);
        if (!children.contains(product.subcategory)) {
          children.add(product.subcategory);
        }
      }
    }
    final groups = context.read<ProductProvider>().groups;
    for (final group in groups.where((item) => !item.isSubgroup)) {
      if (!categories.contains(group.name)) categories.add(group.name);
      final children = groups.where((item) => item.parentId == group.id);
      final names =
          subcategoriesByCategory.putIfAbsent(group.name, () => <String>[]);
      for (final child in children) {
        if (!names.contains(child.name)) names.add(child.name);
      }
    }
    if (widget.product == null) _suggestNextCode();
  }

  Future<void> _suggestNextCode() async {
    try {
      final nextCode =
          await context.read<ProductProvider>().fetchNextProductCode();
      if (mounted && code.text.trim().isEmpty) {
        setState(() => code.text = nextCode.toString());
      }
    } catch (_) {
      // Si falla, el usuario completa el código manualmente.
    }
  }

  @override
  void dispose() {
    for (final c in [
      name,
      code,
      category,
      subcategory,
      cost,
      price,
      description,
      tax,
      currentStock,
      minimumStock,
      idealStock
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  double _number(TextEditingController c) =>
      double.tryParse(c.text.replaceAll(',', '.')) ?? 0;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 850;
    final editor = Form(
      key: _formKey,
      child: Column(children: [
        _topTabs(),
        Expanded(
          child: wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 270, child: _verticalSummary()),
                    Expanded(child: _content()),
                  ],
                )
              : Column(children: [
                  _compactSummary(false),
                  Expanded(child: _content()),
                ]),
        ),
      ]),
    );

    if (widget.embedded) {
      return ColoredBox(
        color: const Color(0xFFF5F5F8),
        child: Column(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: Colors.white,
            child: Row(children: [
              IconButton(
                onPressed: widget.onCancel,
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Volver a productos',
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.product == null ? 'Nuevo producto' : 'Editar producto',
                  style: GoogleFonts.poppins(
                    color: const Color(0xFF2D2260),
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: _save,
                icon: const Icon(Icons.save_rounded),
                label: const Text('Guardar'),
              ),
            ]),
          ),
          Expanded(child: editor),
        ]),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      appBar: AppBar(
        title: Text(
            widget.product == null ? 'Nuevo producto' : 'Editar producto',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
        actions: [
          Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Guardar')))
        ],
      ),
      body: editor,
    );
  }

  Widget _compactSummary(bool wide) => Container(
        margin: EdgeInsets.fromLTRB(wide ? 20 : 12, 14, wide ? 20 : 12, 0),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE7E3F4)),
        ),
        child: Row(children: [
          InkWell(
            onTap: _pickProductImage,
            borderRadius: BorderRadius.circular(12),
            child: Stack(children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: const Color(0xFFF0EEF8),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: _productImage(size: 30),
              ),
              const Positioned(
                right: 3,
                bottom: 3,
                child: CircleAvatar(
                  radius: 10,
                  backgroundColor: Color(0xFF6C5CE7),
                  child:
                      Icon(Icons.edit_rounded, color: Colors.white, size: 11),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name.text.isEmpty ? 'Nuevo producto' : name.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        color: const Color(0xFF2D2260),
                        fontWeight: FontWeight.w700)),
                Text(code.text.isEmpty ? 'Sin código' : code.text,
                    style: const TextStyle(
                        color: Color(0xFF6B6589), fontSize: 12)),
              ],
            ),
          ),
          if (wide) ...[
            _summaryValue('Costo', _number(cost)),
            const SizedBox(width: 24),
            _summaryValue('Precio', _number(price), strong: true),
          ] else
            _summaryValue('Precio', _number(price), strong: true),
        ]),
      );

  Widget _verticalSummary() => Container(
        margin: const EdgeInsets.fromLTRB(20, 10, 0, 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7E3F4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: InkWell(
                onTap: _pickProductImage,
                borderRadius: BorderRadius.circular(16),
                child: Stack(children: [
                  Container(
                    width: 170,
                    height: 170,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0EEF8),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: _productImage(size: 52),
                  ),
                  const Positioned(
                    right: 5,
                    bottom: 5,
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: Color(0xFF6C5CE7),
                      child: Icon(Icons.edit_rounded,
                          color: Colors.white, size: 14),
                    ),
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              name.text.isEmpty ? 'Nuevo producto' : name.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: const Color(0xFF2D2260),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            Text(
              code.text.isEmpty ? 'Sin código' : 'Código: ${code.text}',
              style: const TextStyle(color: Color(0xFF6B6589), fontSize: 12),
            ),
            const Divider(height: 32),
            _verticalValue('Costo sin IVA', _withoutTax(cost)),
            const SizedBox(height: 10),
            _verticalValue('Costo con IVA', _number(cost)),
            const SizedBox(height: 16),
            _verticalValue('Precio sin IVA', _withoutTax(price)),
            const SizedBox(height: 10),
            _verticalValue('Precio con IVA', _number(price), strong: true),
          ],
        ),
      );

  Widget _productImage({required double size}) {
    if (productImage != null) {
      return Image.memory(productImage!, fit: BoxFit.cover);
    }
    final imageUrl = initial.imageUrl;
    if (imageUrl != null && imageUrl.isNotEmpty) {
      final provider = context.read<ProductProvider>();
      return Image.network(
        provider.resolveImageUrl(imageUrl),
        headers: provider.imageHeaders,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const Icon(
          Icons.broken_image_outlined,
          color: Color(0xFFB0A8D8),
          size: 38,
        ),
      );
    }
    return Icon(Icons.add_photo_alternate_outlined,
        color: const Color(0xFFB0A8D8), size: size);
  }

  Widget _verticalValue(String label, double value, {bool strong = false}) =>
      Row(children: [
        Expanded(
          child: Text(label,
              style: const TextStyle(color: Color(0xFF6B6589), fontSize: 11)),
        ),
        Text(
          '\$${value.toStringAsFixed(2)}',
          style: GoogleFonts.poppins(
            color: strong ? const Color(0xFF6C5CE7) : const Color(0xFF2D2260),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ]);

  Widget _summaryValue(String label, double value, {bool strong = false}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(label,
              style: const TextStyle(color: Color(0xFF6B6589), fontSize: 11)),
          Text('\$ ${value.toStringAsFixed(2)}',
              style: GoogleFonts.poppins(
                color:
                    strong ? const Color(0xFF6C5CE7) : const Color(0xFF2D2260),
                fontWeight: FontWeight.w700,
              )),
        ],
      );

  Future<void> _pickProductImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result?.files.first.bytes != null && mounted) {
      setState(() => productImage = result!.files.first.bytes);
    }
  }

  Widget _topTabs() => Container(
        height: 64,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(vertical: 10),
          itemCount: _labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (_, i) => ChoiceChip(
            avatar: Icon(_icons[i], size: 17),
            label: Text(_labels[i]),
            selected: section == i,
            onSelected: (_) => setState(() => section = i),
          ),
        ),
      );

  Widget _content() => Container(
      margin: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(children: [
        Expanded(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24), child: _sectionBody()))
      ]));

  Widget _sectionBody() {
    switch (section) {
      case 1:
        return _taxes();
      case 2:
        return _stock();
      case 3:
        return _placeholder('Escribí las instrucciones de preparación.');
      case 4:
        return _description();
      default:
        return _general();
    }
  }

  Widget _general() => _fields([
        _codeField(),
        _field('Nombre', name, required: true),
        _dropdown(
            'Tipo de producto',
            type,
            [
              'Producto simple',
              'Producto compuesto',
              // 'Ingrediente', // Se habilitará junto con Recetas.
            ],
            (v) => setState(() => type = v!)),
        _calculatedMoney('Costo sin IVA', _withoutTax(cost)),
        _money('Costo con IVA', cost),
        _calculatedMoney('Precio sin IVA', _withoutTax(price)),
        _money('Precio con IVA', price),
        _categoryPicker('Rubro', category, categories),
        _categoryPicker(
          'Sub Rubro',
          subcategory,
          subcategoriesByCategory[category.text] ?? const <String>[],
          parentRequired: true,
        ),
        _checks([
          _check('Muestra en delivery', delivery, (v) => delivery = v),
          _check('Muestra en salón', salon, (v) => salon = v),
          _check(
              'Mostrar en carta digital', digitalMenu, (v) => digitalMenu = v)
        ]),
      ]);

  Widget _taxes() {
    final provider = context.read<ProductProvider>();
    final taxes = provider.taxes;
    ProductTax? selected;
    for (final item in taxes) {
      if (item.id == selectedTaxId) selected = item;
    }
    return _fields([
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: taxes.any((item) => item.id == selectedTaxId)
                ? selectedTaxId
                : null,
            decoration: const InputDecoration(labelText: 'Alícuota'),
            hint: const Text('Seleccioná una alícuota'),
            items: taxes
                .map((item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(item.name),
                    ))
                .toList(),
            onChanged: (value) {
              final chosen = taxes.firstWhere((item) => item.id == value);
              setState(() {
                selectedTaxId = chosen.id;
                tax.text = chosen.percentage.toString();
              });
            },
            validator: (value) =>
                value == null ? 'Seleccioná una alícuota' : null,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          height: 56,
          child: OutlinedButton(
            onPressed: _addTax,
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ]),
      _readOnly('Descripción', selected?.description ?? ''),
      _readOnly(
          'Porcentaje', selected == null ? '' : '${selected.percentage} %'),
    ]);
  }

  Future<void> _addTax() async {
    final taxResult = await showDialog<ProductTax>(
      context: context,
      builder: (_) => const _TaxDialog(),
    );
    if (taxResult == null || !mounted) return;
    try {
      final savedTax = await context.read<ProductProvider>().saveTax(taxResult);
      if (!mounted) return;
      setState(() {
        selectedTaxId = savedTax.id;
        tax.text = savedTax.percentage.toString();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alícuota agregada correctamente')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  Widget _stock() => _fields([
        _dropdown(
            'Operación de cantidad',
            quantityOperation,
            ['Entero', 'Decimal'],
            (value) => setState(() => quantityOperation = value!)),
        _field('Stock actual', currentStock, number: true),
        _field('Stock mínimo', minimumStock, number: true),
        _field('Stock ideal', idealStock, number: true),
        Align(
          alignment: Alignment.centerLeft,
          child: Text('Actualizar sobre',
              style: GoogleFonts.poppins(
                  color: const Color(0xFF2D2260), fontWeight: FontWeight.w600)),
        ),
        Wrap(spacing: 12, children: [
          SizedBox(
            width: 180,
            child: RadioListTile<String>(
              value: 'Producto',
              groupValue: stockUpdatesOn,
              title: const Text('Producto'),
              contentPadding: EdgeInsets.zero,
              onChanged: (value) => setState(() => stockUpdatesOn = value!),
            ),
          ),
          SizedBox(
            width: 180,
            child: RadioListTile<String>(
              value: 'Ingrediente',
              groupValue: stockUpdatesOn,
              title: const Text('Ingrediente'),
              contentPadding: EdgeInsets.zero,
              onChanged: (value) => setState(() => stockUpdatesOn = value!),
            ),
          ),
        ]),
        _checks([
          _check('Tiene alarma de stock', stockAlarm, (v) => stockAlarm = v),
          _check(
              'Alarma de stock mínimo', minimumAlarm, (v) => minimumAlarm = v),
          _check(
              'Comprobar stock al vender', checkOnSale, (v) => checkOnSale = v)
        ])
      ]);

  Widget _description() => TextFormField(
      controller: description,
      maxLines: 10,
      decoration: const InputDecoration(
          labelText: 'Descripción del producto', alignLabelWithHint: true));
  Widget _placeholder(String text) => Center(
      child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(children: [
            const Icon(Icons.construction_rounded,
                size: 54, color: Color(0xFFB0A8D8)),
            const SizedBox(height: 14),
            Text(text, textAlign: TextAlign.center)
          ])));
  Widget _fields(List<Widget> children) => ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 850),
      child: Column(
          children: children
              .map((w) =>
                  Padding(padding: const EdgeInsets.only(bottom: 16), child: w))
              .toList()));
  Widget _field(String label, TextEditingController c,
          {bool required = false, bool number = false}) =>
      TextFormField(
          controller: c,
          keyboardType: number ? TextInputType.number : null,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(labelText: label),
          validator: required
              ? (v) =>
                  v == null || v.trim().isEmpty ? 'Campo obligatorio' : null
              : null);
  Widget _codeField() => TextFormField(
        controller: code,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Código'),
        validator: (value) {
          final parsed = int.tryParse((value ?? '').trim());
          if (parsed == null || parsed <= 0) {
            return 'Ingresá un código numérico mayor que cero';
          }
          final duplicated = context.read<ProductProvider>().products.any(
                (product) =>
                    product.code == parsed.toString() &&
                    product.id != widget.product?.id,
              );
          return duplicated ? 'Este código ya está en uso' : null;
        },
      );
  Widget _money(String label, TextEditingController c,
          {bool required = false}) =>
      _field(label, c, required: required, number: true);
  double _withoutTax(TextEditingController controller) {
    final rate = _number(tax);
    final divisor = 1 + (rate / 100);
    return divisor <= 0 ? _number(controller) : _number(controller) / divisor;
  }

  Widget _calculatedMoney(String label, double value) => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixText: '\$  ',
          filled: true,
          fillColor: const Color(0xFFF0F0F2),
        ),
        child: Text(
          value.toStringAsFixed(2),
          textAlign: TextAlign.right,
          style: GoogleFonts.poppins(
            color: const Color(0xFF5F5B70),
            fontWeight: FontWeight.w500,
          ),
        ),
      );

  Widget _readOnly(String label, String value) => InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF0F0F2),
        ),
        child: Text(value.isEmpty ? '—' : value),
      );
  Widget _categoryPicker(
          String label, TextEditingController controller, List<String> options,
          {bool parentRequired = false}) =>
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: options.contains(controller.text) ? controller.text : null,
            decoration: InputDecoration(labelText: label),
            hint: Text(parentRequired && category.text.isEmpty
                ? 'Primero seleccioná un rubro'
                : options.isEmpty
                    ? 'No hay opciones, agregá una'
                    : 'Seleccioná un ${label.toLowerCase()}'),
            items: options
                .map((item) => DropdownMenuItem(value: item, child: Text(item)))
                .toList(),
            onChanged: parentRequired && category.text.isEmpty
                ? null
                : (value) => setState(() {
                      final previous = controller.text;
                      controller.text = value ?? '';
                      if (!parentRequired && previous != controller.text) {
                        subcategory.clear();
                      }
                    }),
            validator: (value) => value == null || value.isEmpty
                ? 'Seleccioná o agregá una opción'
                : null,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 52,
          height: 56,
          child: OutlinedButton(
            onPressed: parentRequired && category.text.isEmpty
                ? null
                : () => _addCategory(
                      label,
                      controller,
                      options,
                      parentRequired: parentRequired,
                    ),
            style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
            child: const Icon(Icons.add_rounded),
          ),
        ),
      ]);

  Future<void> _addCategory(
      String label, TextEditingController controller, List<String> options,
      {bool parentRequired = false}) async {
    final provider = context.read<ProductProvider>();
    final parent = parentRequired
        ? provider.groups
            .where((item) => !item.isSubgroup && item.name == category.text)
            .firstOrNull
        : null;
    var parentId = parent?.id;
    if (parentRequired && parentId == null) {
      final generatedParent = ProductGroup(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: category.text,
      );
      await provider.saveGroup(generatedParent);
      parentId = generatedParent.id;
    }
    if (!mounted) return;
    final value = await showDialog<ProductGroup>(
      context: context,
      builder: (_) => _GroupDialog(
        isSubgroup: parentRequired,
        parentName: category.text,
        parentId: parentId,
      ),
    );
    if (value == null || !mounted) return;
    await provider.saveGroup(value);
    if (!mounted) return;
    setState(() {
      if (parentRequired) {
        final children = subcategoriesByCategory.putIfAbsent(
            category.text, () => <String>[]);
        if (!children.contains(value.name)) children.add(value.name);
      } else if (!categories.contains(value.name)) {
        categories.add(value.name);
        subcategory.clear();
      }
      controller.text = value.name;
    });
  }

  Widget _dropdown(String label, String value, List<String> options,
          ValueChanged<String?> changed) =>
      DropdownButtonFormField<String>(
          value: value,
          decoration: InputDecoration(labelText: label),
          items: options
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: changed);
  Widget _checks(List<Widget> values) =>
      Wrap(spacing: 16, runSpacing: 4, children: values);
  Widget _check(String label, bool value, ValueChanged<bool> changed) =>
      FilterChip(
          label: Text(label),
          selected: value,
          onSelected: (v) => setState(() => changed(v)));

  void _save() {
    if (!_formKey.currentState!.validate()) {
      setState(() => section = 0);
      return;
    }
    final p = initial;
    final result = p.copyWith(
        name: name.text.trim(),
        code: code.text.trim(),
        category: category.text.trim(),
        subcategory: subcategory.text.trim(),
        description: description.text.trim(),
        type: type,
        cost: _number(cost),
        price: _number(price),
        taxRate: _number(tax),
        taxId: selectedTaxId ?? '',
        minimumStock: _number(minimumStock),
        idealStock: _number(idealStock),
        stockAlarm: stockAlarm,
        minimumStockAlarm: minimumAlarm,
        checkStockOnSale: checkOnSale,
        stockUpdatesOn: stockUpdatesOn,
        quantityOperation: quantityOperation,
        currentStock: _number(currentStock),
        showDelivery: delivery,
        showSalon: salon,
        showDigitalMenu: digitalMenu);
    final productWithImage = result.copyWith(
      imageBase64: productImage == null
          ? result.imageBase64
          : base64Encode(productImage!),
    );
    if (widget.embedded && widget.onSaved != null) {
      widget.onSaved!(productWithImage);
    } else {
      Navigator.pop(context, productWithImage);
    }
  }

  static const _labels = [
    'General',
    'Impuestos',
    'Stock',
    // 'Receta', // Pendiente para una próxima etapa.
    'Preparación',
    'Descripción'
  ];
  static const _icons = [
    Icons.info_rounded,
    Icons.credit_card_rounded,
    Icons.inventory_2_rounded,
    // Icons.receipt_long_rounded, // Receta.
    Icons.restaurant_rounded,
    Icons.notes_rounded
  ];
}

class _TaxDialog extends StatefulWidget {
  const _TaxDialog();

  @override
  State<_TaxDialog> createState() => _TaxDialogState();
}

class _TaxDialogState extends State<_TaxDialog> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final description = TextEditingController();
  final percentage = TextEditingController();

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    percentage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Agregar alícuota'),
        content: SizedBox(
          width: 520,
          child: Form(
            key: formKey,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextFormField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Nombre'),
                validator: _required,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: description,
                minLines: 2,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Descripción'),
                validator: _required,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: percentage,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Porcentaje',
                  suffixText: '%',
                ),
                validator: (value) {
                  final parsed =
                      double.tryParse((value ?? '').replaceAll(',', '.'));
                  if (parsed == null || parsed < 0 || parsed > 100) {
                    return 'Ingresá un porcentaje entre 0 y 100';
                  }
                  return null;
                },
              ),
            ]),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: save,
            icon: const Icon(Icons.save_rounded),
            label: const Text('Guardar'),
          ),
        ],
      );

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Campo obligatorio' : null;

  void save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ProductTax(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        description: description.text.trim(),
        percentage: double.parse(percentage.text.replaceAll(',', '.')),
      ),
    );
  }
}

Future<ProductGroup?> showProductGroupDialog(
  BuildContext context, {
  required bool isSubgroup,
  required String parentName,
  required String? parentId,
}) =>
    showDialog<ProductGroup>(
      context: context,
      builder: (_) => _GroupDialog(
        isSubgroup: isSubgroup,
        parentName: parentName,
        parentId: parentId,
      ),
    );

class _GroupDialog extends StatefulWidget {
  final bool isSubgroup;
  final String parentName;
  final String? parentId;
  const _GroupDialog({
    required this.isSubgroup,
    required this.parentName,
    required this.parentId,
  });

  @override
  State<_GroupDialog> createState() => _GroupDialogState();
}

class _GroupDialogState extends State<_GroupDialog> {
  final formKey = GlobalKey<FormState>();
  final name = TextEditingController();
  final description = TextEditingController();
  String observationType = 'Sin observaciones';
  Uint8List? imageBytes;
  bool products = true;
  bool ingredients = false;
  bool delivery = true;
  bool salon = true;
  bool digitalMenu = true;

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result?.files.first.bytes != null && mounted) {
      setState(() => imageBytes = result!.files.first.bytes);
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    const neutral = Color(0xFF64676C);
    final neutralTheme = baseTheme.copyWith(
      colorScheme: baseTheme.colorScheme.copyWith(
        primary: neutral,
        secondary: neutral,
        surface: const Color(0xFFF5F5F3),
      ),
      inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
        fillColor: const Color(0xFFFAFAF8),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: neutral, width: 2),
        ),
      ),
    );
    return Theme(
      data: neutralTheme,
      child: Dialog(
        backgroundColor: const Color(0xFFF5F5F3),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFD0D1CE)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620, maxHeight: 760),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.isSubgroup
                        ? 'Nuevo Sub Rubro de ${widget.parentName}'
                        : 'Nuevo Rubro',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF45474A),
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Center(
                    child: InkWell(
                      onTap: pickImage,
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(children: [
                        Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE3E4E1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: imageBytes == null
                              ? const Icon(Icons.add_photo_alternate_outlined,
                                  size: 42, color: Color(0xFF85888B))
                              : Image.memory(imageBytes!, fit: BoxFit.cover),
                        ),
                        const Positioned(
                          right: 5,
                          top: 5,
                          child: CircleAvatar(
                            radius: 15,
                            backgroundColor: Color(0xFF64676C),
                            child: Icon(Icons.edit_rounded,
                                color: Colors.white, size: 15),
                          ),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: name,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Nombre'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Ingresá un nombre'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: description,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Descripción'),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: observationType,
                    decoration:
                        const InputDecoration(labelText: 'Tipo de observación'),
                    items: const [
                      'Sin observaciones',
                      'Observación libre',
                      'Observación obligatoria'
                    ]
                        .map((item) =>
                            DropdownMenuItem(value: item, child: Text(item)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => observationType = value!),
                  ),
                  const SizedBox(height: 14),
                  Wrap(spacing: 8, runSpacing: 4, children: [
                    _option('Aplicar en productos', products,
                        (value) => products = value),
                    // La aplicación en ingredientes se habilitará con Recetas.
                    _option('Aplicar en delivery', delivery,
                        (value) => delivery = value),
                    _option(
                        'Aplicar en salón', salon, (value) => salon = value),
                    _option('Mostrar en carta digital', digitalMenu,
                        (value) => digitalMenu = value),
                  ]),
                  const SizedBox(height: 24),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar'),
                    ),
                    const SizedBox(width: 10),
                    FilledButton.icon(
                      onPressed: save,
                      icon: const Icon(Icons.save_rounded),
                      label: const Text('Guardar'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _option(String label, bool value, ValueChanged<bool> onChanged) =>
      FilterChip(
        label: Text(label),
        selected: value,
        onSelected: (selected) => setState(() => onChanged(selected)),
      );

  void save() {
    if (!formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      ProductGroup(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: name.text.trim(),
        description: description.text.trim(),
        observationType: observationType,
        parentId: widget.isSubgroup ? widget.parentId : null,
        imageBase64: imageBytes == null ? null : base64Encode(imageBytes!),
        applyProducts: products,
        applyIngredients: ingredients,
        applyDelivery: delivery,
        applySalon: salon,
        showDigitalMenu: digitalMenu,
      ),
    );
  }
}
