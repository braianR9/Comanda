import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'purchase_api.dart';

String purchaseDocument(Map r) =>
    '${r['documentType']} ${r['letter'] ?? ''} ${(r['pointOfSale'] ?? 0).toString().padLeft(5, '0')}-${r['number']}';
String localDate(dynamic value) {
  final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  return d == null
      ? ''
      : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class PurchasesScreen extends StatefulWidget {
  const PurchasesScreen({super.key});
  @override
  State<PurchasesScreen> createState() => _PurchasesScreenState();
}

class _PurchasesScreenState extends State<PurchasesScreen> {
  late PurchaseApi api;
  List<dynamic> rows = [];
  String status = '';
  String? error;
  bool loading = true;
  int page = 1, pages = 1;
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
      final d = await api.call('purchases?status=$status&page=$page');
      if (mounted) {
        rows = d['items'];
        pages = max(1, d['totalPages'] as int);
      }
    } catch (e) {
      if (mounted) error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> open([int? id]) async {
    await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => PurchaseEditor(api: api, id: id)));
    if (mounted) load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Compras'), actions: [
        IconButton(
            onPressed: loading ? null : load, icon: const Icon(Icons.refresh)),
        TextButton.icon(
            onPressed: () => open(),
            icon: const Icon(Icons.add),
            label: const Text('Cargar compra'))
      ]),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'Sucursal: ${context.read<AuthProvider>().session!.sucursal.nombre}'),
              const Text(
                  'Borrador: pendiente de control. Controlado: productos ingresados al stock.'),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Estado'),
                  items: const [
                    DropdownMenuItem(value: '', child: Text('Todos')),
                    DropdownMenuItem(
                        value: 'Borrador', child: Text('Borrador')),
                    DropdownMenuItem(
                        value: 'Controlado', child: Text('Controlado')),
                    DropdownMenuItem(value: 'Anulado', child: Text('Anulado'))
                  ],
                  onChanged: loading
                      ? null
                      : (v) {
                          status = v!;
                          page = 1;
                          load();
                        })
            ])),
        Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(child: Text(error!))
                    : rows.isEmpty
                        ? const Center(
                            child: Text('No hay compras para mostrar.'))
                        : ListView.builder(
                            itemCount: rows.length,
                            itemBuilder: (context, i) {
                              final r = rows[i] as Map;
                              return Card(
                                  child: ListTile(
                                      title: Text(
                                          '${r['supplierName']} · ${purchaseDocument(r)}'),
                                      subtitle: Text(
                                          '${r['status']} · Cargó: ${r['createdByName']} · ${localDate(r['createdAt'])}'),
                                      trailing: const Icon(Icons.chevron_right),
                                      onTap: () => open(r['id'])));
                            })),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          IconButton(
              onPressed: loading || page <= 1
                  ? null
                  : () {
                      page--;
                      load();
                    },
              icon: const Icon(Icons.chevron_left)),
          Text('Página $page de $pages'),
          IconButton(
              onPressed: loading || page >= pages
                  ? null
                  : () {
                      page++;
                      load();
                    },
              icon: const Icon(Icons.chevron_right))
        ]),
      ]));
}

class _PurchaseLine {
  final int id;
  final String name;
  final TextEditingController quantity, cost;
  _PurchaseLine(this.id, this.name, {dynamic q = 1, dynamic price = 0})
      : quantity = TextEditingController(text: q.toString()),
        cost = TextEditingController(text: price.toString());
  void dispose() {
    quantity.dispose();
    cost.dispose();
  }

  Map<String, dynamic> json() => {
        'productId': id,
        'quantity': double.parse(quantity.text.replaceAll(',', '.')),
        'unitCost': double.parse(cost.text.replaceAll(',', '.'))
      };
}

class PurchaseEditor extends StatefulWidget {
  final PurchaseApi api;
  final int? id;
  const PurchaseEditor({super.key, required this.api, this.id});
  @override
  State<PurchaseEditor> createState() => _PurchaseEditorState();
}

class _PurchaseEditorState extends State<PurchaseEditor> {
  final form = GlobalKey<FormState>();
  final number = TextEditingController(),
      point = TextEditingController(),
      total = TextEditingController(),
      notes = TextEditingController();
  final lines = <_PurchaseLine>[];
  late String requestKey;
  int? id, supplier;
  int version = 0;
  String type = 'Remito', letter = 'A', status = 'Borrador';
  DateTime date = DateTime.now();
  List<dynamic> suppliers = [], available = [], history = [];
  Map<String, dynamic>? purchase;
  bool loading = true, busy = false, productsLoading = false, dirty = false;
  String? error;
  bool get editable => status == 'Borrador';
  @override
  void initState() {
    super.initState();
    id = widget.id;
    requestKey = List.generate(
            24,
            (_) =>
                Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
    load();
  }

  @override
  void dispose() {
    for (final c in [number, point, total, notes]) {
      c.dispose();
    }
    for (final l in lines) {
      l.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final s = await widget.api.call('suppliers');
      final d = id == null ? null : await widget.api.call('purchases/$id');
      if (!mounted) return;
      suppliers = s;
      if (d != null) {
        final p = Map<String, dynamic>.from(d['purchase']);
        purchase = p;
        history = d['history'];
        supplier = p['supplierId'];
        version = p['version'];
        requestKey = p['requestKey'];
        status = p['status'];
        type = p['documentType'];
        letter = p['letter'] == '' ? 'A' : p['letter'];
        number.text = p['number'];
        point.text = p['pointOfSale'].toString();
        total.text = p['documentTotal']?.toString() ?? '';
        notes.text = p['notes'];
        date = DateTime.parse(p['documentDate']);
        for (final l in lines) {
          l.dispose();
        }
        lines.clear();
        for (final r in p['items']) {
          lines.add(_PurchaseLine(r['productId'], r['productName'],
              q: r['quantity'], price: r['unitCost']));
        }
      }
      if (supplier != null && editable) {
        final sd = await widget.api.call('suppliers/$supplier');
        if (mounted) available = sd['products'];
      }
      dirty = false;
    } catch (e) {
      if (mounted) error = e.toString();
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> selectSupplier(int? value) async {
    if (value == supplier) return;
    if (lines.isNotEmpty) {
      final ok = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
                  title: const Text('Cambiar proveedor'),
                  content: const Text(
                      'Se quitarán los productos de esta compra para elegir los del nuevo proveedor.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Volver')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Cambiar'))
                  ]));
      if (ok != true || !mounted) {
        setState(() {});
        return;
      }
    }
    setState(() {
      supplier = value;
      available = [];
      productsLoading = true;
      dirty = true;
      for (final l in lines) {
        l.dispose();
      }
      lines.clear();
    });
    try {
      final d = await widget.api.call('suppliers/$value');
      if (mounted) available = d['products'];
    } catch (e) {
      if (mounted) snack(e.toString());
    } finally {
      if (mounted) setState(() => productsLoading = false);
    }
  }

  Future<void> add() async {
    if (supplier == null) {
      snack('Seleccioná un proveedor.');
      return;
    }
    final options = available
        .where((p) =>
            p['activo'] == true && !lines.any((l) => l.id == p['productId']))
        .toList();
    String search = '';
    final selected = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: const Text('Productos del proveedor'),
                    content: SizedBox(
                        width: 500,
                        height: 400,
                        child: Column(children: [
                          TextField(
                              decoration: const InputDecoration(
                                  labelText: 'Buscar por nombre o código'),
                              onChanged: (v) =>
                                  update(() => search = v.toLowerCase())),
                          Expanded(
                              child: options.isEmpty
                                  ? const Center(
                                      child: Text(
                                          'Asociá productos simples activos en Compras → Proveedores.'))
                                  : ListView(children: [
                                      for (final p in options.where((p) =>
                                          '${p['name']} ${p['code']}'
                                              .toLowerCase()
                                              .contains(search)))
                                        ListTile(
                                            title: Text(p['name']),
                                            subtitle: Text(p['code'] ?? ''),
                                            onTap: () => Navigator.pop(context,
                                                Map<String, dynamic>.from(p)))
                                    ]))
                        ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cerrar'))
                    ])));
    if (selected != null && mounted) {
      setState(() {
        lines.add(_PurchaseLine(selected['productId'], selected['name']));
        dirty = true;
      });
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (supplier == null || lines.isEmpty) {
      snack('Seleccioná proveedor y al menos un producto.');
      return;
    }
    setState(() => busy = true);
    try {
      final d = await widget.api.call(
          id == null ? 'purchases' : 'purchases/$id',
          method: id == null ? 'POST' : 'PUT',
          body: {
            'supplierId': supplier,
            'documentType': type,
            'letter': type == 'Factura' ? letter : '',
            'pointOfSale': int.tryParse(point.text) ?? 0,
            'number': number.text.trim(),
            'documentDate': date.toIso8601String().split('T').first,
            'documentTotal': total.text.trim().isEmpty
                ? null
                : double.parse(total.text.replaceAll(',', '.')),
            'notes': notes.text.trim(),
            'items': lines.map((l) => l.json()).toList(),
            'version': version,
            'requestKey': requestKey
          });
      if (!mounted) return;
      id = d['purchase']['id'];
      await load();
      if (mounted) snack('Borrador guardado. Todavía no ingresó al stock.');
    } catch (e) {
      if (mounted) snack(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(bool control) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, update) => AlertDialog(
                    title: Text(control
                        ? 'Controlar e ingresar al stock'
                        : 'Anular borrador'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(control
                          ? 'Se ingresarán ${lines.length} productos a ${this.context.read<AuthProvider>().session!.sucursal.nombre}. Después no se podrá editar esta compra.'
                          : 'La compra quedará anulada y conservará su historial.'),
                      const SizedBox(height: 16),
                      TextField(
                          controller: reason,
                          maxLength: 1000,
                          decoration: InputDecoration(
                              labelText: control
                                  ? 'Observación del control (opcional)'
                                  : 'Motivo obligatorio'),
                          onChanged: (_) => update(() {}))
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Volver')),
                      FilledButton(
                          onPressed: !control && reason.text.trim().isEmpty
                              ? null
                              : () => Navigator.pop(context, true),
                          child: Text(control ? 'Confirmar ingreso' : 'Anular'))
                    ])));
    final text = reason
        .text; // El diálogo conserva el controlador durante su animación de cierre.
    if (confirmed != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.call('purchases/$id/${control ? 'control' : 'cancel'}',
          method: 'POST', body: {'version': version, 'reason': text});
      if (mounted) {
        await load();
        if (mounted) {
          snack(control
              ? 'Compra controlada: stock actualizado.'
              : 'Borrador anulado.');
        }
      }
    } catch (e) {
      if (mounted) snack(e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String? numeric(String? v, {bool quantity = false, bool optional = false}) {
    if (optional && (v ?? '').trim().isEmpty) return null;
    final n = double.tryParse((v ?? '').replaceAll(',', '.'));
    if (n == null ||
        !n.isFinite ||
        n < 0 ||
        (quantity && n == 0) ||
        n > (quantity ? 999999999999.999 : 9999999999999.99)) {
      return 'Número inválido';
    }
    final digits = quantity ? 3 : 2;
    final factor = pow(10, digits);
    if ((n * factor - (n * factor).round()).abs() > 0.00001) {
      return 'Hasta $digits decimales';
    }
    return null;
  }

  Widget audit(dynamic h) {
    Map snapshot = {};
    try {
      snapshot = jsonDecode(h['snapshot'] ?? '{}') as Map;
    } catch (_) {}
    return Card(
        child: ExpansionTile(
            title: Text('${h['action']} · ${h['userName']}'),
            subtitle: Text(
                '${localDate(h['date'])}${(h['reason'] ?? '') == '' ? '' : ' · ${h['reason']}'}'),
            children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        'Proveedor: ${snapshot['SupplierName'] ?? ''} · ${snapshot['DocumentType'] ?? ''} ${snapshot['Letter'] ?? ''} ${snapshot['PointOfSale'] ?? ''}-${snapshot['Number'] ?? ''}'),
                    Text(
                        'Fecha: ${snapshot['DocumentDate'] ?? ''} · Total comprobante: ${snapshot['DocumentTotal'] ?? 'Sin informar'}'),
                    if ((snapshot['Notes'] ?? '') != '')
                      Text('Observaciones: ${snapshot['Notes']}'),
                    for (final r in snapshot['Items'] as List? ?? [])
                      Text(
                          '${r['ProductName']} · ${r['Quantity']} × \$${r['UnitCost']}')
                  ]))
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final manager = context.read<AuthProvider>().session!.canAccessMasters;
    final calculated = lines.fold<double>(
        0,
        (sum, l) =>
            sum +
            (double.tryParse(l.quantity.text.replaceAll(',', '.')) ?? 0) *
                (double.tryParse(l.cost.text.replaceAll(',', '.')) ?? 0));
    return Scaffold(
        appBar: AppBar(
            title: Text(id == null ? 'Cargar compra' : 'Compra #$id · $status'),
            actions: [
              if (!loading)
                IconButton(
                    tooltip: 'Actualizar',
                    onPressed: busy || dirty ? null : load,
                    icon: const Icon(Icons.refresh))
            ]),
        body: loading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Text(error!),
                    TextButton(onPressed: load, child: const Text('Reintentar'))
                  ]))
                : AbsorbPointer(
                    absorbing: busy,
                    child:
                        ListView(padding: const EdgeInsets.all(24), children: [
                      if (purchase != null)
                        Text(
                            'Cargó: ${purchase!['createdByName']} · ${localDate(purchase!['createdAt'])}${purchase!['controlledByName'] == null ? '' : '\nControló: ${purchase!['controlledByName']} · ${localDate(purchase!['controlledAt'])}'}'),
                      const SizedBox(height: 16),
                      AbsorbPointer(
                          absorbing: !editable,
                          child: Form(
                              key: form,
                              onChanged: () {
                                if (!dirty) setState(() => dirty = true);
                              },
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    DropdownButtonFormField<int>(
                                        key: ValueKey(supplier),
                                        initialValue: supplier,
                                        decoration: const InputDecoration(
                                            labelText: 'Proveedor'),
                                        items: [
                                          for (final s in suppliers.where((s) =>
                                              s['active'] == true ||
                                              s['id'] == supplier))
                                            DropdownMenuItem(
                                                value: s['id'] as int,
                                                child: Text(
                                                    '${s['name']}${s['active'] == true ? '' : ' (inactivo)'}'))
                                        ],
                                        onChanged: productsLoading
                                            ? null
                                            : selectSupplier),
                                    const SizedBox(height: 16),
                                    DropdownButtonFormField<String>(
                                        initialValue: type,
                                        decoration: const InputDecoration(
                                            labelText: 'Comprobante recibido'),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'Remito',
                                              child: Text('Remito')),
                                          DropdownMenuItem(
                                              value: 'Factura',
                                              child: Text('Factura'))
                                        ],
                                        onChanged: (v) => setState(() {
                                              type = v!;
                                              dirty = true;
                                            })),
                                    if (type == 'Factura')
                                      DropdownButtonFormField<String>(
                                          initialValue: letter,
                                          decoration: const InputDecoration(
                                              labelText: 'Letra'),
                                          items: [
                                            for (final l in [
                                              'A',
                                              'B',
                                              'C',
                                              'M',
                                              'E'
                                            ])
                                              DropdownMenuItem(
                                                  value: l, child: Text(l))
                                          ],
                                          onChanged: (v) => setState(() {
                                                letter = v!;
                                                dirty = true;
                                              })),
                                    TextFormField(
                                        controller: point,
                                        keyboardType: TextInputType.number,
                                        maxLength: 5,
                                        decoration: const InputDecoration(
                                            labelText:
                                                'Punto de venta (opcional en remito)'),
                                        validator: (v) {
                                          if (type == 'Remito' && v!.isEmpty) {
                                            return null;
                                          }
                                          final n = int.tryParse(v ?? '');
                                          return n == null ||
                                                  n < 0 ||
                                                  n > 99999 ||
                                                  (type == 'Factura' && n == 0)
                                              ? 'Punto de venta inválido'
                                              : null;
                                        }),
                                    TextFormField(
                                        controller: number,
                                        maxLength: 30,
                                        decoration: const InputDecoration(
                                            labelText:
                                                'Número del comprobante'),
                                        validator: (v) =>
                                            (v ?? '').trim().isEmpty
                                                ? 'Ingresá el número'
                                                : null),
                                    TextButton.icon(
                                        onPressed: () async {
                                          final d = await showDatePicker(
                                              context: context,
                                              initialDate: date,
                                              firstDate: DateTime(2000),
                                              lastDate: DateTime(2100));
                                          if (d != null && mounted) {
                                            setState(() {
                                              date = d;
                                              dirty = true;
                                            });
                                          }
                                        },
                                        icon: const Icon(Icons.calendar_month),
                                        label: Text(
                                            'Fecha: ${date.day}/${date.month}/${date.year}')),
                                    TextFormField(
                                        controller: total,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        decoration: const InputDecoration(
                                            labelText:
                                                'Total del comprobante (opcional, con impuestos)'),
                                        validator: (v) =>
                                            numeric(v, optional: true)),
                                    const SizedBox(height: 16),
                                    TextFormField(
                                        controller: notes,
                                        maxLength: 1000,
                                        decoration: const InputDecoration(
                                            labelText: 'Observaciones')),
                                    const SizedBox(height: 16),
                                    Text('Productos recibidos',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleLarge),
                                    const Text(
                                        'Cantidades en la unidad de stock del producto. Cargá el costo unitario del comprobante.'),
                                    for (final l in lines)
                                      Card(
                                          key: ValueKey(l.id),
                                          child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: Column(children: [
                                                Row(children: [
                                                  Expanded(child: Text(l.name)),
                                                  if (editable)
                                                    IconButton(
                                                        onPressed: () =>
                                                            setState(() {
                                                              lines.remove(l);
                                                              dirty = true;
                                                            }),
                                                        icon: const Icon(Icons
                                                            .delete_outline))
                                                ]),
                                                Row(children: [
                                                  Expanded(
                                                      child: TextFormField(
                                                          controller:
                                                              l.quantity,
                                                          keyboardType:
                                                              const TextInputType
                                                                  .numberWithOptions(
                                                                  decimal:
                                                                      true),
                                                          decoration:
                                                              const InputDecoration(
                                                                  labelText:
                                                                      'Cantidad'),
                                                          validator: (v) =>
                                                              numeric(v,
                                                                  quantity:
                                                                      true),
                                                          onChanged: (_) =>
                                                              setState(() =>
                                                                  dirty =
                                                                      true))),
                                                  const SizedBox(width: 16),
                                                  Expanded(
                                                      child: TextFormField(
                                                          controller: l.cost,
                                                          keyboardType:
                                                              const TextInputType
                                                                  .numberWithOptions(
                                                                  decimal:
                                                                      true),
                                                          decoration:
                                                              const InputDecoration(
                                                                  labelText:
                                                                      'Costo unitario'),
                                                          validator: numeric,
                                                          onChanged: (_) =>
                                                              setState(() =>
                                                                  dirty =
                                                                      true)))
                                                ])
                                              ]))),
                                    if (editable)
                                      OutlinedButton.icon(
                                          onPressed:
                                              productsLoading ? null : add,
                                          icon: const Icon(Icons.add),
                                          label: Text(productsLoading
                                              ? 'Cargando productos…'
                                              : 'Agregar producto del proveedor')),
                                    Padding(
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        child: Text(
                                            'Suma de productos: \$${calculated.toStringAsFixed(2)} · No modifica precios de venta.')),
                                  ]))),
                      if (editable)
                        Wrap(spacing: 12, runSpacing: 12, children: [
                          FilledButton(
                              onPressed: busy || productsLoading ? null : save,
                              child: Text(
                                  busy ? 'Procesando…' : 'Guardar borrador')),
                          if (id != null && manager) ...[
                            FilledButton.icon(
                                onPressed:
                                    busy || dirty ? null : () => action(true),
                                icon: const Icon(Icons.fact_check),
                                label: const Text(
                                    'Controlar e ingresar al stock')),
                            OutlinedButton(
                                onPressed:
                                    busy || dirty ? null : () => action(false),
                                child: const Text('Anular borrador'))
                          ]
                        ]),
                      if (editable && dirty && id != null)
                        const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child:
                                Text('Guardá los cambios antes de controlar.')),
                      const SizedBox(height: 24),
                      if (history.isNotEmpty)
                        Text('Historial de la compra',
                            style: Theme.of(context).textTheme.titleLarge),
                      ...history.map(audit),
                    ])));
  }
}
