import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../models/product.dart';
import '../../config/api_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import 'product_editor_screen.dart';

class ProductsScreen extends StatefulWidget {
  final bool embedded;
  final ValueChanged<Product?>? onOpenEditor;
  const ProductsScreen({
    super.key,
    this.embedded = false,
    this.onOpenEditor,
  });

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  Timer? _searchTimer;

  @override
  void initState() {
    super.initState();
    final companyId = context.read<AuthProvider>().session!.idEmpresa;
    final token = context.read<AuthProvider>().session!.token;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ProductProvider>().load(companyId, token: token),
    );
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProductProvider>();
    final query = _query.trim().toLowerCase();
    final products = provider.products.where((product) {
      return query.isEmpty ||
          product.name.toLowerCase().contains(query) ||
          product.category.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.name.compareTo(b.name));

    final content = SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 100),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Mis productos',
                        style: GoogleFonts.poppins(
                          color: const Color(0xFF2D2260),
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: () => _openProductForm(),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Nuevo producto'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Expanded(
                  child: Column(children: [
                    Padding(
                      padding: EdgeInsets.zero,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) {
                          setState(() => _query = value);
                          _searchTimer?.cancel();
                          _searchTimer =
                              Timer(const Duration(milliseconds: 400), () {
                            if (!mounted) return;
                            context
                                .read<ProductProvider>()
                                .loadProductsPage(page: 1, text: value);
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre o categoría',
                          prefixIcon: const Icon(Icons.search_rounded),
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _query = '');
                                    context
                                        .read<ProductProvider>()
                                        .loadProductsPage(page: 1);
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Expanded(
                      child: provider.loading
                          ? const Center(child: CircularProgressIndicator())
                          : provider.errorMessage != null
                              ? _ApiError(
                                  message: provider.errorMessage!,
                                  onRetry: () {
                                    final session =
                                        context.read<AuthProvider>().session!;
                                    provider.load(session.idEmpresa,
                                        token: session.token, force: true);
                                  },
                                )
                              : products.isEmpty
                                  ? _EmptyProducts(hasSearch: query.isNotEmpty)
                                  : LayoutBuilder(
                                      builder: (context, constraints) {
                                      if (constraints.maxWidth >= 760) {
                                        return _ProductsTable(
                                          products: products,
                                          onEdit: _openProductForm,
                                          onToggle: provider.setActive,
                                          onDelete: _confirmDelete,
                                        );
                                      }
                                      return ListView.separated(
                                        padding: const EdgeInsets.all(12),
                                        itemCount: products.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 12),
                                        itemBuilder: (_, index) => _ProductCard(
                                          product: products[index],
                                          onEdit: () =>
                                              _openProductForm(products[index]),
                                          onToggle: (value) =>
                                              provider.setActive(
                                                  products[index], value),
                                          onDelete: () =>
                                              _confirmDelete(products[index]),
                                        ),
                                      );
                                    }),
                    ),
                    if (!provider.loading && provider.errorMessage == null) ...[
                      const SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.zero,
                        child: _PaginationBar(
                          currentPage: provider.currentPage,
                          totalPages: provider.totalPages,
                          totalItems: provider.totalItems,
                          pageSize: ProductProvider.pageSize,
                          onPageChanged: (page) => provider.loadProductsPage(
                              page: page, text: _query),
                        ),
                      ),
                    ],
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.embedded) {
      return ColoredBox(color: const Color(0xFFF5F5F8), child: content);
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F8),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        foregroundColor: const Color(0xFF3D2D8A),
        title: Text('Mis productos',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openProductForm(),
        backgroundColor: const Color(0xFF6C5CE7),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text('Nuevo producto',
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
      ),
      body: content,
    );
  }

  Future<void> _openProductForm([Product? product]) async {
    Product? editorProduct = product;
    if (product != null) {
      try {
        editorProduct =
            await context.read<ProductProvider>().getById(product.id);
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(error.toString().replaceFirst('Exception: ', ''))),
        );
        return;
      }
    }
    if (widget.embedded && widget.onOpenEditor != null) {
      widget.onOpenEditor!(editorProduct);
      return;
    }
    if (!mounted) return;
    final result = await Navigator.of(context).push<Product>(
      MaterialPageRoute(
        builder: (_) => ProductEditorScreen(product: editorProduct),
      ),
    );
    if (result != null && mounted) {
      await context.read<ProductProvider>().save(result);
    }
  }

  Future<void> _confirmDelete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar producto'),
        content: Text('¿Querés eliminar “${product.name}”?'),
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
    if (confirmed == true && mounted) {
      await context.read<ProductProvider>().remove(product.id);
    }
  }
}

class _EmptyProducts extends StatelessWidget {
  final bool hasSearch;
  const _EmptyProducts({required this.hasSearch});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              hasSearch ? Icons.search_off_rounded : Icons.inventory_2_outlined,
              size: 64,
              color: const Color(0xFFB0A8D8)),
          const SizedBox(height: 16),
          Text(
              hasSearch
                  ? 'No encontramos productos'
                  : 'Todavía no hay productos',
              style: GoogleFonts.poppins(
                  color: const Color(0xFF3D2D8A),
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
              hasSearch
                  ? 'Probá con otra búsqueda.'
                  : 'Creá el primero desde el botón “Nuevo producto”.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: const Color(0xFF6B6589))),
        ]),
      );
}

class _ApiError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ApiError({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.cloud_off_rounded,
              size: 58, color: Color(0xFFEF4444)),
          const SizedBox(height: 14),
          Text('No se pudieron cargar los productos',
              style: GoogleFonts.poppins(
                  color: const Color(0xFF2D2260),
                  fontSize: 17,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Text(message,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: const Color(0xFF6B6589))),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Reintentar'),
          ),
        ]),
      );
}

class _PaginationBar extends StatelessWidget {
  final int currentPage;
  final int totalPages;
  final int totalItems;
  final int pageSize;
  final ValueChanged<int> onPageChanged;
  const _PaginationBar({
    required this.currentPage,
    required this.totalPages,
    required this.totalItems,
    required this.pageSize,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final from = totalItems == 0 ? 0 : (currentPage - 1) * pageSize + 1;
    final to = (currentPage * pageSize).clamp(0, totalItems);
    return Row(children: [
      Text('$from–$to de $totalItems',
          style: GoogleFonts.poppins(
              color: const Color(0xFF6B6589), fontSize: 12)),
      const Spacer(),
      IconButton(
        tooltip: 'Página anterior',
        onPressed:
            currentPage > 1 ? () => onPageChanged(currentPage - 1) : null,
        icon: const Icon(Icons.chevron_left_rounded),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEDE9FF),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('$currentPage de ${totalPages < 1 ? 1 : totalPages}',
            style: GoogleFonts.poppins(
                color: const Color(0xFF3D2D8A),
                fontSize: 12,
                fontWeight: FontWeight.w600)),
      ),
      IconButton(
        tooltip: 'Página siguiente',
        onPressed: currentPage < totalPages
            ? () => onPageChanged(currentPage + 1)
            : null,
        icon: const Icon(Icons.chevron_right_rounded),
      ),
    ]);
  }
}

class _ProductsTable extends StatelessWidget {
  final List<Product> products;
  final ValueChanged<Product> onEdit;
  final void Function(Product product, bool active) onToggle;
  final ValueChanged<Product> onDelete;
  const _ProductsTable({
    required this.products,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: EdgeInsets.zero,
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0xFFE7E3F4)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Scrollbar(
          thumbVisibility: true,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 1100,
              child: ListView(
                children: [
                  DataTable(
                    headingRowColor:
                        MaterialStateProperty.all(const Color(0xFFF0F0F2)),
                    headingRowHeight: 44,
                    dataRowMinHeight: 58,
                    dataRowMaxHeight: 58,
                    columnSpacing: 18,
                    columns: const [
                      DataColumn(label: Text('Imagen')),
                      DataColumn(label: Text('Código')),
                      DataColumn(label: Text('Nombre')),
                      DataColumn(label: Text('Precio')),
                      DataColumn(label: Text('Rubro')),
                      DataColumn(label: Text('Sub Rubro')),
                      DataColumn(label: Text('Estado')),
                      DataColumn(label: Text('')),
                    ],
                    rows: products
                        .map((product) => DataRow(cells: [
                              DataCell(
                                  _ProductImage(product: product, size: 38)),
                              DataCell(Text(product.code)),
                              DataCell(SizedBox(
                                width: 135,
                                child: Text(product.name,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w600)),
                              )),
                              DataCell(_MoneyCell(
                                gross: product.price,
                                taxRate: product.taxRate,
                              )),
                              DataCell(Text(product.category)),
                              DataCell(Text(product.subcategory)),
                              DataCell(Switch(
                                value: product.active,
                                onChanged: (value) => onToggle(product, value),
                              )),
                              DataCell(PopupMenuButton<String>(
                                onSelected: (value) => value == 'edit'
                                    ? onEdit(product)
                                    : onDelete(product),
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                      value: 'edit', child: Text('Editar')),
                                  PopupMenuItem(
                                      value: 'delete', child: Text('Eliminar')),
                                ],
                              )),
                            ]))
                        .toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}

class _MoneyCell extends StatelessWidget {
  final double gross;
  final double taxRate;
  const _MoneyCell({required this.gross, required this.taxRate});

  @override
  Widget build(BuildContext context) {
    final net = gross / (1 + taxRate / 100);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('\$ ${gross.toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        Text('Sin IVA: \$ ${net.toStringAsFixed(2)}',
            style: const TextStyle(color: Color(0xFF8A849F), fontSize: 11)),
      ],
    );
  }
}

class _ProductImage extends StatelessWidget {
  final Product product;
  final double size;
  const _ProductImage({required this.product, required this.size});

  @override
  Widget build(BuildContext context) {
    Widget image;
    if (product.imageBase64 != null) {
      image =
          Image.memory(base64Decode(product.imageBase64!), fit: BoxFit.cover);
    } else if (product.imageUrl != null && product.imageUrl!.isNotEmpty) {
      image = Image.network(
        product.imageUrl!.startsWith('http')
            ? product.imageUrl!
            : '${ApiConfig.baseUrl}${product.imageUrl}',
        fit: BoxFit.cover,
        headers: const {ApiConfig.apiKeyHeader: ApiConfig.apiKeyValue},
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image_outlined, color: Color(0xFFB0A8D8)),
      );
    } else {
      image = const Icon(Icons.icecream_rounded, color: Color(0xFF6C5CE7));
    }
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFEDE9FF),
        borderRadius: BorderRadius.circular(10),
      ),
      clipBehavior: Clip.antiAlias,
      child: image,
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Product product;
  final VoidCallback onEdit;
  final ValueChanged<bool> onToggle;
  final VoidCallback onDelete;
  const _ProductCard({
    required this.product,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) => Card(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: Color(0xFFE7E3F4)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: const Color(0xFFEDE9FF),
                    borderRadius: BorderRadius.circular(12)),
                child: product.imageBase64 == null && product.imageUrl == null
                    ? const Icon(Icons.icecream_rounded,
                        color: Color(0xFF6C5CE7))
                    : product.imageBase64 == null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              product.imageUrl!.startsWith('http')
                                  ? product.imageUrl!
                                  : '${ApiConfig.baseUrl}${product.imageUrl}',
                              width: 24,
                              height: 24,
                              fit: BoxFit.cover,
                              headers: const {
                                ApiConfig.apiKeyHeader: ApiConfig.apiKeyValue
                              },
                            ),
                          )
                        : ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.memory(
                              base64Decode(product.imageBase64!),
                              width: 24,
                              height: 24,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(
                                Icons.broken_image_outlined,
                                color: Color(0xFF6C5CE7),
                              ),
                            ),
                          ),
              ),
              const Spacer(),
              PopupMenuButton<String>(
                onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(value: 'delete', child: Text('Eliminar')),
                ],
              ),
            ]),
            const SizedBox(height: 12),
            Text(product.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    color: const Color(0xFF2D2260),
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            Text(product.category,
                style: GoogleFonts.poppins(
                    color: const Color(0xFF6B6589), fontSize: 12)),
            const Spacer(),
            Row(children: [
              Text('\$ ${product.price.toStringAsFixed(2)}',
                  style: GoogleFonts.poppins(
                      color: const Color(0xFF6C5CE7),
                      fontSize: 17,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Text(product.active ? 'Activo' : 'Inactivo',
                  style: GoogleFonts.poppins(fontSize: 11)),
              Switch(value: product.active, onChanged: onToggle),
            ]),
          ]),
        ),
      );
}
