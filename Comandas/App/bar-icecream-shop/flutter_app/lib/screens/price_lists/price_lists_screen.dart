import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/price_list.dart';
import '../../providers/auth_provider.dart';
import '../../providers/price_list_provider.dart';
import '../../providers/product_provider.dart';

class PriceListsScreen extends StatefulWidget {
  final bool embedded;
  const PriceListsScreen({super.key, this.embedded = false});

  @override
  State<PriceListsScreen> createState() => _PriceListsScreenState();
}

class _PriceListsScreenState extends State<PriceListsScreen> {
  PriceList? _selected;
  bool _initialLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<AuthProvider>().session!;
    await Future.wait([
      context.read<PriceListProvider>().load(session.token),
      context
          .read<ProductProvider>()
          .load(session.idEmpresa, token: session.token),
    ]);
    if (mounted) setState(() => _initialLoading = false);
  }

  void _showError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(error.toString().replaceFirst('Exception: ', ''))));
  }

  Future<void> _create() async {
    final result = await showDialog<_CreateListResult>(
        context: context, builder: (_) => const _CreatePriceListDialog());
    if (result == null || !mounted) return;
    try {
      await context.read<PriceListProvider>().create(
          nombre: result.nombre, copiarDesdeListaId: result.copiarDesdeListaId);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _rename(PriceList lista) async {
    final controller = TextEditingController(text: lista.nombre);
    final nombre = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Renombrar lista'),
        content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Nombre')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Guardar')),
        ],
      ),
    );
    if (nombre == null || nombre.isEmpty || !mounted) return;
    try {
      await context.read<PriceListProvider>().rename(lista.id, nombre);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _toggleActive(PriceList lista, bool activa) async {
    try {
      await context.read<PriceListProvider>().setActive(lista.id, activa);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _setDefault(PriceList lista) async {
    try {
      await context.read<PriceListProvider>().setDefault(lista.id);
    } catch (error) {
      _showError(error);
    }
  }

  Future<void> _delete(PriceList lista) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar lista'),
        content: Text(
            '¿Eliminar la lista "${lista.nombre}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await context.read<PriceListProvider>().remove(lista.id);
    } catch (error) {
      _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
            child: _initialLoading
                ? const Center(child: CircularProgressIndicator())
                : _selected == null
                    ? _buildOverview()
                    : _PriceListDetail(
                        lista: _selected!,
                        onBack: () => setState(() => _selected = null),
                      ),
          ),
        ),
      ),
    );
    return widget.embedded
        ? ColoredBox(color: const Color(0xFFF5F5F8), child: content)
        : Scaffold(backgroundColor: const Color(0xFFF5F5F8), body: content);
  }

  Widget _buildOverview() {
    final provider = context.watch<PriceListProvider>();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('Listas de precios',
              style: GoogleFonts.poppins(
                  color: const Color(0xFF2D2260),
                  fontSize: 26,
                  fontWeight: FontWeight.w800)),
        ),
        FilledButton.icon(
            onPressed: _create,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Nueva lista')),
      ]),
      const SizedBox(height: 20),
      if (provider.lists.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text('Todavía no hay listas de precios.',
              style: GoogleFonts.poppins(color: const Color(0xFF9E8FCC))),
        )
      else
        ...provider.lists.map((lista) => Card(
              margin: const EdgeInsets.only(bottom: 10),
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade200)),
              child: ListTile(
                onTap: () => setState(() => _selected = lista),
                title: Row(children: [
                  Text(lista.nombre,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                  if (lista.esPredeterminada) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: const Color(0xFFEDE9FF),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text('Predeterminada',
                          style: GoogleFonts.poppins(
                              fontSize: 11, color: const Color(0xFF3D2D8A))),
                    ),
                  ],
                ]),
                subtitle: Text(
                    '${lista.cantidadPrecios} productos con precio configurado',
                    style: GoogleFonts.poppins(
                        fontSize: 12, color: const Color(0xFF9E8FCC))),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Switch(
                      value: lista.activa,
                      onChanged: (v) => _toggleActive(lista, v)),
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          _rename(lista);
                        case 'default':
                          _setDefault(lista);
                        case 'delete':
                          _delete(lista);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(
                          value: 'rename', child: Text('Renombrar')),
                      if (!lista.esPredeterminada)
                        const PopupMenuItem(
                            value: 'default',
                            child: Text('Marcar como predeterminada')),
                      if (!lista.esPredeterminada)
                        const PopupMenuItem(
                            value: 'delete', child: Text('Eliminar')),
                    ],
                  ),
                ]),
              ),
            )),
    ]);
  }
}

class _CreateListResult {
  final String nombre;
  final int? copiarDesdeListaId;
  const _CreateListResult(this.nombre, this.copiarDesdeListaId);
}

class _CreatePriceListDialog extends StatefulWidget {
  const _CreatePriceListDialog();
  @override
  State<_CreatePriceListDialog> createState() => _CreatePriceListDialogState();
}

class _CreatePriceListDialogState extends State<_CreatePriceListDialog> {
  final _nombre = TextEditingController();
  int? _copiarDesdeListaId;

  @override
  void dispose() {
    _nombre.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lists = context.watch<PriceListProvider>().lists;
    return AlertDialog(
      title: const Text('Nueva lista de precios'),
      content: SizedBox(
        width: 380,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: _nombre,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration:
                  const InputDecoration(labelText: 'Nombre de la lista')),
          const SizedBox(height: 16),
          Align(
              alignment: Alignment.centerLeft,
              child: Text('Crear a partir de:',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600))),
          RadioListTile<int?>(
            value: null,
            groupValue: _copiarDesdeListaId,
            onChanged: (value) => setState(() => _copiarDesdeListaId = value),
            title: const Text('Lista vacía'),
            dense: true,
          ),
          for (final lista in lists)
            RadioListTile<int?>(
              value: lista.id,
              groupValue: _copiarDesdeListaId,
              onChanged: (value) => setState(() => _copiarDesdeListaId = value),
              title: Text('Copiar desde: ${lista.nombre}'),
              dense: true,
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: _nombre.text.trim().isEmpty
              ? null
              : () => Navigator.pop(context,
                  _CreateListResult(_nombre.text.trim(), _copiarDesdeListaId)),
          child: const Text('Crear'),
        ),
      ],
    );
  }
}

class _PriceListDetail extends StatefulWidget {
  final PriceList lista;
  final VoidCallback onBack;
  const _PriceListDetail({required this.lista, required this.onBack});

  @override
  State<_PriceListDetail> createState() => _PriceListDetailState();
}

class _PriceListDetailState extends State<_PriceListDetail> {
  String? _idRubro;
  String? _idSubRubro;
  final _searchController = TextEditingController();
  String _texto = '';
  PagedProductPrices? _page;
  bool _loading = true;
  int _currentPage = 1;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetch({int page = 1}) async {
    setState(() => _loading = true);
    try {
      final result = await context.read<PriceListProvider>().getPrices(
            widget.lista.id,
            idRubro: _idRubro == null ? null : int.tryParse(_idRubro!),
            idSubRubro: _idSubRubro == null ? null : int.tryParse(_idSubRubro!),
            texto: _texto,
            page: page,
          );
      if (!mounted) return;
      setState(() {
        _page = result;
        _currentPage = page;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _setPrice(ProductPrice item, double precio) async {
    try {
      await context
          .read<PriceListProvider>()
          .setPrice(widget.lista.id, item.idProducto, precio);
      if (!mounted) return;
      setState(() {
        final items = _page!.items
            .map((p) => p.idProducto == item.idProducto
                ? p.copyWith(precio: precio)
                : p)
            .toList();
        _page = PagedProductPrices(
            items: items,
            page: _page!.page,
            totalPages: _page!.totalPages,
            totalItems: _page!.totalItems);
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _bulkEdit() async {
    final applied = await showDialog<bool>(
      context: context,
      builder: (_) => _BulkPriceDialog(
        listaId: widget.lista.id,
        idRubro: _idRubro == null ? null : int.tryParse(_idRubro!),
        idSubRubro: _idSubRubro == null ? null : int.tryParse(_idSubRubro!),
        texto: _texto,
      ),
    );
    if (applied == true) await _fetch(page: _currentPage);
  }

  @override
  Widget build(BuildContext context) {
    final groups = context.watch<ProductProvider>().groups;
    final rubros = groups.where((g) => !g.isSubgroup).toList();
    final subrubros =
        groups.where((g) => g.isSubgroup && g.parentId == _idRubro).toList();
    final page = _page;

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(
            onPressed: widget.onBack,
            icon: const Icon(Icons.arrow_back_rounded)),
        Expanded(
          child: Text('Lista: ${widget.lista.nombre}',
              style: GoogleFonts.poppins(
                  color: const Color(0xFF2D2260),
                  fontSize: 22,
                  fontWeight: FontWeight.w800)),
        ),
        OutlinedButton.icon(
            onPressed: _bulkEdit,
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Modificación masiva')),
      ]),
      const SizedBox(height: 16),
      Wrap(spacing: 12, runSpacing: 8, children: [
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            value: _idRubro,
            decoration: const InputDecoration(labelText: 'Rubro'),
            items: [
              const DropdownMenuItem(
                  value: null, child: Text('Todos los rubros')),
              for (final rubro in rubros)
                DropdownMenuItem(value: rubro.id, child: Text(rubro.name)),
            ],
            onChanged: (value) {
              setState(() {
                _idRubro = value;
                _idSubRubro = null;
              });
              _fetch();
            },
          ),
        ),
        SizedBox(
          width: 220,
          child: DropdownButtonFormField<String?>(
            value: _idSubRubro,
            decoration: const InputDecoration(labelText: 'Subrubro'),
            items: [
              const DropdownMenuItem(
                  value: null, child: Text('Todos los subrubros')),
              for (final sub in subrubros)
                DropdownMenuItem(value: sub.id, child: Text(sub.name)),
            ],
            onChanged: _idRubro == null
                ? null
                : (value) {
                    setState(() => _idSubRubro = value);
                    _fetch();
                  },
          ),
        ),
        SizedBox(
          width: 260,
          child: TextField(
            controller: _searchController,
            decoration: const InputDecoration(
                labelText: 'Buscar por nombre o código',
                prefixIcon: Icon(Icons.search_rounded)),
            onSubmitted: (value) {
              _texto = value;
              _fetch();
            },
          ),
        ),
      ]),
      const SizedBox(height: 16),
      if (_loading)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator()))
      else if (page == null || page.items.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text('No hay productos para estos filtros.',
              style: GoogleFonts.poppins(color: const Color(0xFF9E8FCC))),
        )
      else ...[
        Card(
          margin: EdgeInsets.zero,
          elevation: 0,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200)),
          child: Column(children: [
            for (final item in page.items)
              _ProductPriceRow(
                key: ValueKey(item.idProducto),
                item: item,
                onChanged: (value) => _setPrice(item, value),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text('${page.totalItems} productos',
              style: GoogleFonts.poppins(
                  fontSize: 12, color: const Color(0xFF6B6280))),
          const Spacer(),
          IconButton(
              onPressed: _currentPage > 1
                  ? () => _fetch(page: _currentPage - 1)
                  : null,
              icon: const Icon(Icons.chevron_left_rounded)),
          Text('$_currentPage de ${page.totalPages < 1 ? 1 : page.totalPages}'),
          IconButton(
              onPressed: _currentPage < page.totalPages
                  ? () => _fetch(page: _currentPage + 1)
                  : null,
              icon: const Icon(Icons.chevron_right_rounded)),
        ]),
      ],
    ]);
  }
}

class _ProductPriceRow extends StatefulWidget {
  final ProductPrice item;
  final ValueChanged<double> onChanged;
  const _ProductPriceRow(
      {super.key, required this.item, required this.onChanged});

  @override
  State<_ProductPriceRow> createState() => _ProductPriceRowState();
}

class _ProductPriceRowState extends State<_ProductPriceRow> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
        text: widget.item.precio?.toStringAsFixed(2) ?? '');
  }

  @override
  void didUpdateWidget(covariant _ProductPriceRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.precio != widget.item.precio) {
      _controller.text = widget.item.precio?.toStringAsFixed(2) ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final parsed = double.tryParse(_controller.text.replaceAll(',', '.'));
    if (parsed == null || parsed < 0) return;
    widget.onChanged(parsed);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(children: [
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.item.nombre,
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
              Text(
                  '${widget.item.codigo} · ${widget.item.rubro.nombre}'
                  '${widget.item.subRubro != null ? ' / ${widget.item.subRubro!.nombre}' : ''}',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: const Color(0xFF9E8FCC))),
            ]),
          ),
          SizedBox(
            width: 140,
            child: TextField(
              controller: _controller,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '\$ ',
                hintText: widget.item.tienePrecio ? null : 'Sin precio',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
              onTapOutside: (_) => _submit(),
            ),
          ),
        ]),
      );
}

class _BulkPriceDialog extends StatefulWidget {
  final int listaId;
  final int? idRubro;
  final int? idSubRubro;
  final String texto;
  const _BulkPriceDialog(
      {required this.listaId,
      this.idRubro,
      this.idSubRubro,
      required this.texto});

  @override
  State<_BulkPriceDialog> createState() => _BulkPriceDialogState();
}

class _BulkPriceDialogState extends State<_BulkPriceDialog> {
  String _operacion = 'AumentarPorcentaje';
  final _valor = TextEditingController();
  List<BulkPricePreviewItem>? _preview;
  bool _loading = false;

  static const _operaciones = {
    'AumentarPorcentaje': 'Aumentar precio por porcentaje',
    'DisminuirPorcentaje': 'Disminuir precio por porcentaje',
    'AumentarImporte': 'Aumentar un importe fijo',
    'DisminuirImporte': 'Disminuir un importe fijo',
  };

  @override
  void dispose() {
    _valor.dispose();
    super.dispose();
  }

  Future<void> _preview_() async {
    final valor = double.tryParse(_valor.text.replaceAll(',', '.'));
    if (valor == null || valor < 0) return;
    setState(() => _loading = true);
    try {
      final preview = await context.read<PriceListProvider>().previewBulk(
            widget.listaId,
            idRubro: widget.idRubro,
            idSubRubro: widget.idSubRubro,
            texto: widget.texto,
            operacion: _operacion,
            valor: valor,
          );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _apply() async {
    final valor = double.tryParse(_valor.text.replaceAll(',', '.'));
    if (valor == null) return;
    setState(() => _loading = true);
    try {
      await context.read<PriceListProvider>().applyBulk(
            widget.listaId,
            idRubro: widget.idRubro,
            idSubRubro: widget.idSubRubro,
            texto: widget.texto,
            operacion: _operacion,
            valor: valor,
          );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    return AlertDialog(
      title: const Text('Modificación masiva de precios'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (preview == null) ...[
              DropdownButtonFormField<String>(
                value: _operacion,
                decoration: const InputDecoration(labelText: 'Operación'),
                items: [
                  for (final entry in _operaciones.entries)
                    DropdownMenuItem(
                        value: entry.key, child: Text(entry.value)),
                ],
                onChanged: (value) => setState(() => _operacion = value!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _valor,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _operacion.contains('Porcentaje')
                      ? 'Porcentaje'
                      : 'Importe',
                  suffixText: _operacion.contains('Porcentaje') ? '%' : null,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                  'Se aplica sobre los productos que coinciden con los filtros actuales de la '
                  'grilla (rubro/subrubro/búsqueda). Los productos sin precio configurado en '
                  'esta lista no se modifican.',
                  style: GoogleFonts.poppins(
                      fontSize: 12, color: const Color(0xFF9E8FCC))),
            ] else if (preview.isEmpty)
              const Text(
                  'No hay productos con precio configurado para estos filtros.')
            else ...[
              Text('${preview.length} productos serán actualizados:',
                  style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: preview.length,
                  itemBuilder: (_, index) {
                    final item = preview[index];
                    return ListTile(
                      dense: true,
                      title: Text(item.nombre),
                      trailing: Text(
                          '\$${(item.precioActual ?? 0).toStringAsFixed(2)} → \$${item.precioNuevo.toStringAsFixed(2)}'),
                    );
                  },
                ),
              ),
            ],
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        if (preview == null)
          FilledButton(
              onPressed: _loading ? null : _preview_,
              child: const Text('Vista previa'))
        else
          FilledButton(
              onPressed: _loading || preview.isEmpty ? null : _apply,
              child: const Text('Confirmar')),
      ],
    );
  }
}
