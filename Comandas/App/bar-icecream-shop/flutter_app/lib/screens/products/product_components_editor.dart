import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/product_component.dart';
import '../../providers/product_provider.dart';

class ProductComponentsEditor extends StatelessWidget {
  final int? productId;
  final List<ProductComponent> components;
  final ValueChanged<List<ProductComponent>> onChanged;
  const ProductComponentsEditor(
      {super.key,
      this.productId,
      required this.components,
      required this.onChanged});

  Future<void> _add(BuildContext context) async {
    final selected = await showDialog<ProductComponent>(
        context: context,
        builder: (_) => SimpleProductPicker(excluded: {
              if (productId != null) productId!,
              ...components.map((c) => c.productId)
            }));
    if (selected != null) onChanged([...components, selected]);
  }

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Composición del producto',
            style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        const Text(
            'Indicá cuánto se usa de cada producto simple por unidad vendida. Al cobrar se descontará el stock de estos componentes en la sucursal.'),
        const SizedBox(height: 12),
        for (final component in components)
          Padding(
              key: ValueKey(component.productId),
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(children: [
                Expanded(child: Text(component.name)),
                const SizedBox(width: 12),
                SizedBox(
                    width: 145,
                    child: TextFormField(
                      initialValue: component.quantity.toString(),
                      decoration: const InputDecoration(
                          labelText: 'Cantidad por unidad'),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      validator: (v) {
                        final q =
                            double.tryParse((v ?? '').replaceAll(',', '.'));
                        if (q == null ||
                            !q.isFinite ||
                            q <= 0 ||
                            q > 999999999999999.999) return 'Cantidad inválida';
                        if ((q * 1000 - (q * 1000).round()).abs() > 0.000001)
                          return 'Máximo 3 decimales';
                        return null;
                      },
                      onChanged: (value) => onChanged([
                        for (final c in components)
                          c.productId == component.productId
                              ? ProductComponent(
                                  productId: c.productId,
                                  name: c.name,
                                  quantity: double.tryParse(
                                          value.replaceAll(',', '.')) ??
                                      0)
                              : c
                      ]),
                    )),
                IconButton(
                    tooltip: 'Quitar componente',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => onChanged(components
                        .where((c) => c.productId != component.productId)
                        .toList())),
              ])),
        Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
                onPressed: () => _add(context),
                icon: const Icon(Icons.add),
                label: const Text('Agregar producto simple'))),
      ]);
}

class SimpleProductPicker extends StatefulWidget {
  final Set<int> excluded;
  const SimpleProductPicker({required this.excluded});
  @override
  State<SimpleProductPicker> createState() => SimpleProductPickerState();
}

class SimpleProductPickerState extends State<SimpleProductPicker> {
  final _search = TextEditingController();
  Timer? _debounce;
  int _generation = 0;
  bool _loading = true;
  String? _error;
  List<ProductComponent> _items = [];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await context
          .read<ProductProvider>()
          .searchSimpleComponents(_search.text.trim());
      if (!mounted || generation != _generation) return;
      setState(() {
        _items =
            items.where((c) => !widget.excluded.contains(c.productId)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Agregar producto simple'),
        content: SizedBox(
            width: 480,
            height: 400,
            child: Column(children: [
              TextField(
                  controller: _search,
                  autofocus: true,
                  decoration: const InputDecoration(
                      labelText: 'Buscar por nombre o código',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (_) {
                    _generation++;
                    _debounce?.cancel();
                    _debounce = Timer(const Duration(milliseconds: 300), _load);
                  }),
              const SizedBox(height: 8),
              const Text(
                  'Hasta 50 resultados. Escribí para encontrar otros productos.'),
              const SizedBox(height: 8),
              Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Column(children: [
                              Text(_error!),
                              TextButton(
                                  onPressed: _load,
                                  child: const Text('Reintentar'))
                            ])
                          : _items.isEmpty
                              ? const Center(
                                  child: Text(
                                      'No hay productos simples disponibles para esta búsqueda.'))
                              : ListView(children: [
                                  for (final item in _items)
                                    ListTile(
                                        title: Text(item.name),
                                        onTap: () =>
                                            Navigator.pop(context, item))
                                ])),
            ])),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'))
        ],
      );
}
