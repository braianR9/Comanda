import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../models/product_component.dart';
import '../products/product_components_editor.dart';
import 'purchase_api.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key});
  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  late PurchaseApi api;
  List<dynamic> rows = [];
  bool loading = true;
  String? error;
  @override
  void initState() {
    super.initState();
    api = PurchaseApi(context.read<AuthProvider>().session!.token);
    load();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final d = await api.call('suppliers');
      if (mounted) rows = d as List;
    } catch (e) {
      if (mounted) error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> edit([int? id]) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SupplierEditor(api: api, id: id)));
    if (mounted) load();
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.read<AuthProvider>().session!.canAccessMasters;
    return Scaffold(
        appBar: AppBar(title: const Text('Compras · Proveedores'), actions: [
          IconButton(onPressed: load, icon: const Icon(Icons.refresh)),
          if (manager)
            TextButton.icon(
                onPressed: () => edit(),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo proveedor'))
        ]),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Text(error!))
                : rows.isEmpty
                    ? const Center(
                        child: Text(
                            'Cargá un proveedor y asociá los productos que le comprás.'))
                    : ListView.builder(
                        itemCount: rows.length,
                        itemBuilder: (context, i) {
                          final r = rows[i];
                          return Card(
                              child: ListTile(
                                  leading:
                                      const Icon(Icons.local_shipping_outlined),
                                  title: Text(
                                      '${r['name']}${r['active'] == true ? '' : ' (inactivo)'}'),
                                  subtitle: Text(
                                      'CUIT: ${r['cuit'] ?? 'Sin cargar'} · ${r['phone'] ?? ''}'),
                                  onTap: () => edit(r['id']),
                                  trailing: const Icon(Icons.chevron_right)));
                        }));
  }
}

class SupplierEditor extends StatefulWidget {
  final PurchaseApi api;
  final int? id;
  const SupplierEditor({super.key, required this.api, this.id});
  @override
  State<SupplierEditor> createState() => _SupplierEditorState();
}

class _SupplierEditorState extends State<SupplierEditor> {
  final form = GlobalKey<FormState>();
  final fields = <String, TextEditingController>{};
  final products = <Map<String, dynamic>>[];
  bool loading = false, saving = false, active = true;
  String? error;
  int version = 0;
  TextEditingController c(String key) =>
      fields.putIfAbsent(key, TextEditingController.new);
  @override
  void initState() {
    super.initState();
    if (widget.id != null) load();
  }

  @override
  void dispose() {
    for (final c in fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    setState(() => loading = true);
    try {
      final d = await widget.api.call('suppliers/${widget.id}');
      if (!mounted) return;
      final s = d['supplier'];
      for (final k in [
        'name',
        'cuit',
        'taxCondition',
        'contact',
        'phone',
        'email',
        'address',
        'notes'
      ]) {
        c(k).text = s[k]?.toString() ?? '';
      }
      active = s['active'];
      version = s['version'];
      products.addAll(
          (d['products'] as List).map((x) => Map<String, dynamic>.from(x)));
    } catch (e) {
      error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> add() async {
    final session = context.read<AuthProvider>().session!;
    await context
        .read<ProductProvider>()
        .load(session.idEmpresa, token: session.token);
    if (!mounted) return;
    final p = await showDialog<ProductComponent>(
        context: context,
        builder: (_) => SimpleProductPicker(
            excluded: products.map((x) => x['productId'] as int).toSet()));
    if (p != null && mounted) {
      setState(() => products.add({
            'productId': p.productId,
            'name': p.name,
            'code': '',
            'activo': true
          }));
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      await widget.api.call(
          widget.id == null ? 'suppliers' : 'suppliers/${widget.id}',
          method: widget.id == null ? 'POST' : 'PUT',
          body: {
            for (final k in [
              'name',
              'cuit',
              'taxCondition',
              'contact',
              'phone',
              'email',
              'address',
              'notes'
            ])
              k: c(k).text.trim(),
            'active': active,
            'version': version,
            'products': products
                .map((p) =>
                    {'productId': p['productId'], 'code': p['code'] ?? ''})
                .toList()
          });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget field(String key, String label, {int max = 200}) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
          controller: c(key),
          maxLength: max,
          decoration: InputDecoration(labelText: label, counterText: ''),
          validator: (v) => key == 'name' && (v ?? '').trim().isEmpty
              ? 'Ingresá el nombre.'
              : null));
  @override
  Widget build(BuildContext context) {
    final manager = context.read<AuthProvider>().session!.canAccessMasters;
    return Scaffold(
        appBar: AppBar(
            title: Text(widget.id == null ? 'Nuevo proveedor' : 'Proveedor')),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(child: Text(error!))
                : AbsorbPointer(
                    absorbing: saving || !manager,
                    child: Form(
                        key: form,
                        child: ListView(
                            padding: const EdgeInsets.all(24),
                            children: [
                              field('name', 'Nombre / razón social'),
                              field('cuit', 'CUIT', max: 20),
                              field('taxCondition', 'Condición frente al IVA',
                                  max: 80),
                              field('contact', 'Persona de contacto', max: 150),
                              field('phone', 'Teléfono', max: 60),
                              field('email', 'Email'),
                              field('address', 'Dirección', max: 300),
                              field('notes', 'Observaciones', max: 1000),
                              SwitchListTile(
                                  value: active,
                                  onChanged: (v) => setState(() => active = v),
                                  title: const Text('Proveedor activo')),
                              const SizedBox(height: 16),
                              Text('Productos que provee',
                                  style:
                                      Theme.of(context).textTheme.titleLarge),
                              const Text(
                                  'Asociá los productos simples existentes que vas a ingresar al stock.'),
                              for (final p in products)
                                Card(
                                    key: ValueKey(p['productId']),
                                    child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(children: [
                                                Expanded(
                                                    child: Text(
                                                        '${p['name']}${p['activo'] == false ? ' (inactivo)' : ''}')),
                                                IconButton(
                                                    onPressed: () => setState(
                                                        () =>
                                                            products.remove(p)),
                                                    icon:
                                                        const Icon(Icons.close))
                                              ]),
                                              TextFormField(
                                                  initialValue: p['code'] ?? '',
                                                  maxLength: 80,
                                                  decoration: const InputDecoration(
                                                      labelText:
                                                          'Código del proveedor (opcional)',
                                                      counterText: ''),
                                                  onChanged: (v) =>
                                                      p['code'] = v)
                                            ]))),
                              OutlinedButton.icon(
                                  onPressed: add,
                                  icon: const Icon(Icons.add),
                                  label: const Text('Asociar producto simple')),
                              const SizedBox(height: 24),
                              if (manager)
                                FilledButton(
                                    onPressed: saving ? null : save,
                                    child: Text(saving
                                        ? 'Guardando…'
                                        : 'Guardar proveedor')),
                            ]))));
  }
}
