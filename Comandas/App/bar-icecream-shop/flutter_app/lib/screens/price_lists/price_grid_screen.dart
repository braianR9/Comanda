import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/price_list.dart';
import '../../providers/price_list_provider.dart';
import '../../providers/product_provider.dart';
import 'price_history_screen.dart';

class PriceGridScreen extends StatefulWidget {
  const PriceGridScreen({super.key});
  @override
  State<PriceGridScreen> createState() => _PriceGridScreenState();
}

class _PriceGridScreenState extends State<PriceGridScreen> {
  final _search = TextEditingController();
  final _edits = <(int, int), String>{};
  final _originals = <(int, int), double?>{};
  final _controllers = <(int, int), TextEditingController>{};
  List<PriceList> _lists = [];
  List<ProductPrice> _products = [];
  final _prices = <(int, int), double?>{};
  int _page = 1, _pages = 1;
  String _query = '';
  int? _rubro;
  bool _loading = true, _saving = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load({int page = 1}) async {
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = context.read<PriceListProvider>();
      final lists = List<PriceList>.of(provider.activeLists);
      final results = await Future.wait(lists.map((l) => provider.getPrices(
          l.id,
          texto: _query,
          idRubro: _rubro,
          page: page,
          pageSize: 25)));
      if (!mounted || generation != _generation) return;
      for (final c in _controllers.values) {
        c.dispose();
      }
      _controllers.clear();
      _prices.clear();
      for (var i = 0; i < lists.length; i++) {
        for (final p in results[i].items) {
          final key = (lists[i].id, p.idProducto);
          _prices[key] = p.precio;
          _controllers[key] =
              TextEditingController(text: _edits[key] ?? _format(p.precio));
        }
      }
      setState(() {
        _lists = lists;
        _products = results.isEmpty ? [] : results.first.items;
        _page = page;
        _pages = results.isEmpty ? 1 : results.first.totalPages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  String _format(double? price) =>
      price?.toStringAsFixed(2).replaceAll('.', ',') ?? '';
  bool _valid(String text) =>
      text.trim().isEmpty ||
      RegExp(r'^\d{1,16}([,.]\d{1,2})?$').hasMatch(text.trim());
  double? _parse(String text) => text.trim().isEmpty
      ? null
      : double.tryParse(text.trim().replaceAll(',', '.'));

  void _edit((int, int) key, String value) {
    setState(() {
      _originals.putIfAbsent(key, () => _prices[key]);
      if (_valid(value) && _parse(value) == _originals[key]) {
        _edits.remove(key);
        _originals.remove(key);
      } else {
        _edits[key] = value;
      }
    });
  }

  Future<bool> _confirmDiscard() async =>
      _edits.isEmpty ||
      await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                      title: const Text('Cambios sin guardar'),
                      content: Text(
                          'Tenés ${_edits.length} precios modificados. ¿Descartar los cambios?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('Seguir editando')),
                        FilledButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('Descartar'))
                      ])) ==
          true;

  Future<void> _discard() async {
    if (!await _confirmDiscard() || !mounted) return;
    setState(() {
      _edits.clear();
      _originals.clear();
    });
    await _load(page: _page);
  }

  Future<void> _save() async {
    if (_edits.values.any((v) => !_valid(v))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Revisá los precios marcados. Usá hasta dos decimales, sin separador de miles.')));
      return;
    }
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Guardar precios'),
                content: Text(
                    'Se guardarán ${_edits.length} cambios juntos. Las celdas vacías quedarán sin precio. Podés revisar y revertir el grupo desde el historial.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Guardar'))
                ]));
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await context.read<PriceListProvider>().saveGrid(_edits.entries
          .map((e) => <String, dynamic>{
                'idListaPrecio': e.key.$1,
                'idProducto': e.key.$2,
                'precioAnterior': _originals[e.key],
                'precioNuevo': _parse(e.value),
              })
          .toList());
      if (!mounted) return;
      setState(() {
        _edits.clear();
        _originals.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Precios guardados. El cambio quedó registrado en el historial.')));
      await _load(page: _page);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups =
        context.watch<ProductProvider>().groups.where((g) => !g.isSubgroup);
    return PopScope(
      canPop: _edits.isEmpty && !_saving,
      onPopInvoked: (didPop) async {
        if (didPop || _saving) return;
        if (await _confirmDiscard() && mounted) {
          setState(() {
            _edits.clear();
            _originals.clear();
          });
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Planilla de precios'), actions: [
          TextButton.icon(
              onPressed: _saving
                  ? null
                  : () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const PriceHistoryScreen()));
                      if (mounted) await _load(page: _page);
                    },
              icon: const Icon(Icons.history),
              label: const Text('Historial'))
        ]),
        body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                      'Compará las listas activas y editá varias celdas. Tab pasa a la siguiente. Vacío significa sin precio; 0 es un precio de cero.'),
                  const SizedBox(height: 12),
                  Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                            width: 260,
                            child: TextField(
                                controller: _search,
                                enabled: !_saving,
                                decoration: const InputDecoration(
                                    labelText: 'Nombre o código',
                                    prefixIcon: Icon(Icons.search)),
                                onSubmitted: (_) {
                                  _query = _search.text;
                                  _load();
                                })),
                        SizedBox(
                            width: 220,
                            child: DropdownButtonFormField<int>(
                                value: _rubro,
                                decoration:
                                    const InputDecoration(labelText: 'Rubro'),
                                isExpanded: true,
                                items: [
                                  const DropdownMenuItem<int>(
                                      value: null, child: Text('Todos')),
                                  for (final g in groups)
                                    DropdownMenuItem(
                                        value: int.parse(g.id),
                                        child: Text(g.name))
                                ],
                                onChanged: _saving
                                    ? null
                                    : (v) {
                                        _rubro = v;
                                        _load();
                                      })),
                        OutlinedButton(
                            onPressed: _saving
                                ? null
                                : () {
                                    _query = _search.text;
                                    _load();
                                  },
                            child: const Text('Buscar')),
                        Text('${_edits.length} cambios pendientes'),
                        FilledButton.icon(
                            onPressed: _saving || _loading || _edits.isEmpty
                                ? null
                                : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(
                                _saving ? 'Guardando…' : 'Guardar cambios')),
                        TextButton(
                            onPressed:
                                _saving || _edits.isEmpty ? null : _discard,
                            child: const Text('Descartar')),
                      ]),
                  const SizedBox(height: 12),
                  if (_error != null)
                    MaterialBanner(content: Text(_error!), actions: [
                      TextButton(
                          onPressed: () => _load(page: _page),
                          child: const Text('Reintentar'))
                    ]),
                  Expanded(
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                              ? const SizedBox.shrink()
                              : _products.isEmpty
                                  ? const Center(
                                      child: Text(
                                          'No hay productos para estos filtros.'))
                                  : SingleChildScrollView(
                                      child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: DataTable(columns: [
                                            const DataColumn(
                                                label: Text('Producto')),
                                            for (final l in _lists)
                                              DataColumn(label: Text(l.nombre))
                                          ], rows: [
                                            for (final p in _products)
                                              DataRow(cells: [
                                                DataCell(SizedBox(
                                                    width: 240,
                                                    child: Text(
                                                        '${p.codigo} · ${p.nombre}'))),
                                                for (final l in _lists)
                                                  DataCell(SizedBox(
                                                      width: 145,
                                                      child: TextField(
                                                          key: ValueKey(
                                                              (l.id, p.idProducto)),
                                                          controller:
                                                              _controllers[(
                                                            l.id,
                                                            p.idProducto
                                                          )],
                                                          enabled: !_saving,
                                                          keyboardType: const TextInputType.numberWithOptions(
                                                              decimal: true),
                                                          decoration: InputDecoration(
                                                              prefixText: '\$',
                                                              hintText:
                                                                  'Sin precio',
                                                              isDense: true,
                                                              filled: _edits
                                                                  .containsKey((
                                                                l.id,
                                                                p.idProducto
                                                              )),
                                                              fillColor: Colors
                                                                  .amber
                                                                  .shade50,
                                                              errorText:
                                                                  _edits.containsKey((l.id, p.idProducto)) && !_valid(_edits[(l.id, p.idProducto)]!)
                                                                      ? 'Precio inválido'
                                                                      : null),
                                                          onChanged: (v) =>
                                                              _edit((l.id, p.idProducto), v))))
                                              ])
                                          ])))),
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    IconButton(
                        onPressed: _saving || _loading || _page <= 1
                            ? null
                            : () => _load(page: _page - 1),
                        icon: const Icon(Icons.chevron_left)),
                    Text('Página $_page de ${_pages < 1 ? 1 : _pages}'),
                    IconButton(
                        onPressed: _saving || _loading || _page >= _pages
                            ? null
                            : () => _load(page: _page + 1),
                        icon: const Icon(Icons.chevron_right)),
                  ]),
                ])),
      ),
    );
  }
}
