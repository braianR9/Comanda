import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/price_list_provider.dart';

class PriceHistoryScreen extends StatefulWidget {
  const PriceHistoryScreen({super.key});
  @override
  State<PriceHistoryScreen> createState() => _PriceHistoryScreenState();
}

class _PriceHistoryScreenState extends State<PriceHistoryScreen> {
  List<dynamic> _items = [];
  int _page = 1, _pages = 1;
  bool _loading = true, _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({int page = 1}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await context.read<PriceListProvider>().history(page);
      if (mounted) {
        setState(() {
          _items = data['items'] as List;
          _page = page;
          _pages = data['totalPages'] as int;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _price(dynamic value) =>
      value == null ? 'Sin precio' : '\$${(value as num).toStringAsFixed(2)}';
  String _date(dynamic value) {
    final d = DateTime.parse(value as String).toLocal();
    String pad(int n) => n.toString().padLeft(2, '0');
    return '${pad(d.day)}/${pad(d.month)}/${d.year} ${pad(d.hour)}:${pad(d.minute)}';
  }

  Future<void> _details(Map<String, dynamic> item) async {
    setState(() => _busy = true);
    try {
      final details = await context
          .read<PriceListProvider>()
          .historyDetails(item['lote'] as String);
      if (!mounted) return;
      final revert = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Detalle del cambio'),
                  content: SizedBox(
                      width: 650,
                      height: 400,
                      child: ListView(children: [
                        Text('${_date(item['fecha'])} · ${item['usuario']}'),
                        Text(item['motivo'] as String),
                        const SizedBox(height: 12),
                        for (final row in details)
                          ListTile(
                              title: Text(
                                  '${row['productoNombre']} · ${row['listaNombre']}'),
                              subtitle: Text(
                                  '${_price(row['precioAnterior'])} → ${_price(row['precioNuevo'])}')),
                        const Text(
                            'Revertir restaura todo el grupo. Si hubo cambios posteriores en alguno de estos precios, la operación se bloqueará.'),
                      ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cerrar')),
                    if (item['revertido'] != true &&
                        !(item['motivo'] as String).startsWith('Reversión'))
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Revertir grupo'))
                  ]));
      if (revert != true || !mounted) return;
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('¿Restaurar los precios anteriores?'),
                  content: Text(
                      'Se revertirán ${details.length} precios y quedará registrado un nuevo movimiento.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Confirmar reversión'))
                  ]));
      if (confirmed != true || !mounted) return;
      await context.read<PriceListProvider>().revert(item['lote'] as String);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Precios anteriores restaurados.')));
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Historial de precios')),
        body: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Text(
                  'Los cambios se registran desde la activación del historial. Tocá un grupo para ver los precios anteriores y nuevos.'),
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(),
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
                                      onPressed: () => _load(page: _page),
                                      child: const Text('Reintentar'))
                                ]))
                          : _items.isEmpty
                              ? const Center(
                                  child: Text(
                                      'Todavía no hay cambios registrados.'))
                              : ListView.builder(
                                  itemCount: _items.length,
                                  itemBuilder: (_, i) {
                                    final item =
                                        _items[i] as Map<String, dynamic>;
                                    return Card(
                                        child: ListTile(
                                            onTap: _busy
                                                ? null
                                                : () => _details(item),
                                            leading: const Icon(
                                                Icons.price_change_outlined),
                                            title: Text(
                                                '${item['motivo']} · ${item['cantidad']} precios'),
                                            subtitle: Text(
                                                '${_date(item['fecha'])} · ${item['usuario']}'),
                                            trailing: item['revertido'] == true
                                                ? const Chip(
                                                    label: Text('Revertido'))
                                                : const Icon(
                                                    Icons.chevron_right)));
                                  })),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                    onPressed: _loading || _busy || _page <= 1
                        ? null
                        : () => _load(page: _page - 1),
                    icon: const Icon(Icons.chevron_left)),
                Text('Página $_page de ${_pages < 1 ? 1 : _pages}'),
                IconButton(
                    onPressed: _loading || _busy || _page >= _pages
                        ? null
                        : () => _load(page: _page + 1),
                    icon: const Icon(Icons.chevron_right)),
              ])
            ])),
      );
}
