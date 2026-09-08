import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../config/api_config.dart';
import '../../models/product.dart';
import '../../models/user_session.dart';
import '../../providers/auth_provider.dart';
import '../../providers/product_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/sector_provider.dart';
import '../auth/login_screen.dart';
import '../clients/clients_screen.dart';
import '../products/product_editor_screen.dart';
import '../products/product_groups_screen.dart';
import '../products/products_screen.dart';
import '../sectors/sectors_screen.dart';
import '../sales/sales_screen.dart';
import '../stock/stock_movements_screen.dart';
import '../sales/sales_catalogs_screen.dart';
import '../printers/printers_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthProvider>().session;
    if (session == null) return const SizedBox.shrink();
    final isWide = MediaQuery.of(context).size.width >= 800;

    return Scaffold(
      body: Stack(
        children: [
          const _HomeBg(),
          SafeArea(
            child: Column(
              children: [
                _TopBar(isWide: isWide, session: session),
                Expanded(
                  child: isWide
                      ? _WideLayout(session: session)
                      : _NarrowLayout(session: session),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Fondo ─────────────────────────────────────────────────────────────────────
class _HomeBg extends StatelessWidget {
  const _HomeBg();
  @override
  Widget build(BuildContext context) {
    return Container(color: const Color(0xFFF5F5F8));
  }
}

// ── Top bar ───────────────────────────────────────────────────────────────────
class _TopBar extends StatelessWidget {
  final bool isWide;
  final UserSession session;
  const _TopBar({required this.isWide, required this.session});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 32 : 20, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const FocoLogo(size: 26, color: Color(0xFF5C4D9B)),
          const SizedBox(width: 10),
          Text(
            'FOCO',
            style: GoogleFonts.poppins(
              color: const Color(0xFF3D2D8A),
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
            ),
          ),
          const Spacer(),
          if (isWide) ...[
            const Icon(Icons.location_on_outlined,
                color: Color(0xFF9E8FCC), size: 14),
            const SizedBox(width: 4),
            Text(
              session.sucursal.nombre,
              style: GoogleFonts.poppins(
                  color: const Color(0xFF9E8FCC), fontSize: 13),
            ),
            const SizedBox(width: 20),
          ],
          _UserChip(session: session),
        ],
      ),
    );
  }
}

// ── Chip de usuario ───────────────────────────────────────────────────────────
class _UserChip extends StatelessWidget {
  final UserSession session;
  const _UserChip({required this.session});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      offset: const Offset(0, 48),
      itemBuilder: (_) => [
        PopupMenuItem(
          value: 'products',
          onTap: () => Future.microtask(() {
            if (!context.mounted) return;
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProductsScreen()),
            );
          }),
          child: Row(
            children: [
              const Icon(Icons.inventory_2_rounded,
                  color: Color(0xFF6C5CE7), size: 18),
              const SizedBox(width: 10),
              Text('Mis productos',
                  style: GoogleFonts.poppins(
                      color: const Color(0xFF3D2D8A), fontSize: 14)),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'logout',
          onTap: () {
            context.read<AuthProvider>().logout();
            Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
              (_) => false,
            );
          },
          child: Row(
            children: [
              const Icon(Icons.logout_rounded,
                  color: Color(0xFF6C5CE7), size: 18),
              const SizedBox(width: 10),
              Text('Cerrar sesión',
                  style: GoogleFonts.poppins(
                      color: const Color(0xFF3D2D8A), fontSize: 14)),
            ],
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEDE9FF),
          borderRadius: BorderRadius.circular(50),
          border: Border.all(color: const Color(0xFFBFB0F0)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 13,
              backgroundColor: const Color(0xFF6C5CE7),
              child: Text(
                session.nombre.isNotEmpty
                    ? session.nombre[0].toUpperCase()
                    : '?',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  session.nombreCompleto,
                  style: GoogleFonts.poppins(
                      color: const Color(0xFF3D2D8A),
                      fontSize: 13,
                      fontWeight: FontWeight.w500),
                ),
                Text(
                  session.rol.nombre,
                  style: GoogleFonts.poppins(
                      color: const Color(0xFF9E8FCC), fontSize: 11),
                ),
              ],
            ),
            const SizedBox(width: 6),
            const Icon(Icons.keyboard_arrow_down_rounded,
                color: Color(0xFF9E8FCC), size: 16),
          ],
        ),
      ),
    );
  }
}

// ── Layouts ───────────────────────────────────────────────────────────────────
class _WideLayout extends StatefulWidget {
  final UserSession session;
  const _WideLayout({required this.session});

  @override
  State<_WideLayout> createState() => _WideLayoutState();
}

class _WideLayoutState extends State<_WideLayout>
    with SingleTickerProviderStateMixin {
  bool _expanded = true;
  int _section = 0;
  bool _productEditorOpen = false;
  Product? _editingProduct;
  late final AnimationController _ctrl;
  late final Animation<double> _widthAnim;

  static const double _kExpanded = 210;
  static const double _kCollapsed = 64;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
    _widthAnim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _ctrl.forward() : _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sidebar + botón toggle superpuesto
        AnimatedBuilder(
          animation: _widthAnim,
          builder: (_, __) {
            final showLabel = _widthAnim.value > 0.5;
            final w = _WideLayoutState._kCollapsed +
                (_WideLayoutState._kExpanded - _WideLayoutState._kCollapsed) *
                    _widthAnim.value;
            return SizedBox(
              // Los 20 px extra pertenecen realmente al layout. De este modo
              // toda la zona táctil del prendedor puede recibir eventos.
              width: w + 20,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: w,
                    child: _Sidebar(
                      widthFactor: _widthAnim.value,
                      expanded: showLabel,
                      section: _section,
                      onSectionChanged: (value) => setState(() {
                        _section = value;
                        if (value != 1) {
                          _productEditorOpen = false;
                          _editingProduct = null;
                        }
                      }),
                    ),
                  ),
                  // El botón queda abrochado al borde: mitad dentro del menú
                  // y mitad sobre el espacio reservado antes del contenido.
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: 40,
                    child: Center(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _toggle,
                          child: SizedBox(
                            width: 40,
                            height: 88,
                            child: Center(
                              child: Container(
                                width: 20,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF6C5CE7),
                                  borderRadius: BorderRadius.circular(10),
                                  border:
                                      Border.all(color: Colors.white, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.15),
                                      blurRadius: 6,
                                    ),
                                  ],
                                ),
                                child: AnimatedRotation(
                                  turns: _expanded ? 0 : 0.5,
                                  duration: const Duration(milliseconds: 220),
                                  child: const Icon(
                                    Icons.chevron_left_rounded,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        Expanded(
          child: _section == 8
              ? const ClientsScreen(embedded: true)
              : _section == 7
                  ? const StockMovementsScreen(embedded: true)
                  : _section == 6
                      ? const PrintersScreen(embedded: true)
                      : _section == 5
                          ? const SalesCatalogsScreen(embedded: true)
                          : _section == 4
                              ? const SalesScreen(embedded: true)
                              : _section == 1
                                  ? _productEditorOpen
                                      ? ProductEditorScreen(
                                          key: ValueKey(_editingProduct?.id ??
                                              'new-product'),
                                          product: _editingProduct,
                                          embedded: true,
                                          onCancel: () => setState(() {
                                            _productEditorOpen = false;
                                            _editingProduct = null;
                                          }),
                                          onSaved: (product) async {
                                            try {
                                              await context
                                                  .read<ProductProvider>()
                                                  .save(product);
                                              if (!mounted) return;
                                              setState(() {
                                                _productEditorOpen = false;
                                                _editingProduct = null;
                                              });
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                    content: Text(
                                                        'Producto guardado correctamente')),
                                              );
                                            } catch (error) {
                                              if (!mounted) return;
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                SnackBar(
                                                  content: Text(error
                                                      .toString()
                                                      .replaceFirst(
                                                          'Exception: ', '')),
                                                ),
                                              );
                                            }
                                          },
                                        )
                                      : ProductsScreen(
                                          embedded: true,
                                          onOpenEditor: (product) =>
                                              setState(() {
                                            _editingProduct = product;
                                            _productEditorOpen = true;
                                          }),
                                        )
                                  : _section == 2
                                      ? const ProductGroupsScreen(
                                          embedded: true)
                                      : _section == 3
                                          ? const SectorsScreen(embedded: true)
                                          : SingleChildScrollView(
                                              padding: const EdgeInsets.all(32),
                                              child: _HomeContent(
                                                  session: widget.session),
                                            ),
        ),
      ],
    );
  }
}

class _NarrowLayout extends StatelessWidget {
  final UserSession session;
  const _NarrowLayout({required this.session});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: _HomeContent(session: session),
    );
  }
}

// ── Sidebar ───────────────────────────────────────────────────────────────────
class _Sidebar extends StatelessWidget {
  final double widthFactor;
  final bool expanded;
  final int section;
  final ValueChanged<int> onSectionChanged;
  const _Sidebar({
    this.widthFactor = 1,
    this.expanded = true,
    required this.section,
    required this.onSectionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final w = _WideLayoutState._kCollapsed +
        (_WideLayoutState._kExpanded - _WideLayoutState._kCollapsed) *
            widthFactor;
    return Container(
      width: w,
      decoration: const BoxDecoration(
        color: Color(0xFF6C5CE7),
        border: Border(
          right: BorderSide(color: Color(0xFF5A4BD1), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SidebarItem(
              icon: Icons.home_rounded,
              label: 'Inicio',
              active: section == 0,
              showLabel: expanded,
              onTap: () => onSectionChanged(0)),
          _SidebarItem(
              icon: Icons.point_of_sale_rounded,
              label: 'Ventas',
              active: section == 4 || section == 7 || section == 8,
              showLabel: expanded),
          if (expanded) ...[
            _SidebarItem(
                icon: Icons.table_restaurant_rounded,
                label: 'Salón',
                active: section == 4,
                showLabel: true,
                nested: true,
                onTap: () => onSectionChanged(4)),
            _SidebarItem(
                icon: Icons.swap_vert_rounded,
                label: 'Movimientos de stock',
                active: section == 7,
                showLabel: true,
                nested: true,
                onTap: () => onSectionChanged(7)),
            _SidebarItem(
                icon: Icons.people_alt_rounded,
                label: 'Clientes',
                active: section == 8,
                showLabel: true,
                nested: true,
                onTap: () => onSectionChanged(8)),
          ] else
            _SidebarItem(
                icon: Icons.table_restaurant_rounded,
                label: 'Salón',
                active: section == 4 || section == 7 || section == 8,
                showLabel: false,
                onTap: () => onSectionChanged(4)),
          _SidebarItem(
              icon: Icons.school_rounded,
              label: 'Maestros',
              active: section == 1 ||
                  section == 2 ||
                  section == 3 ||
                  section == 5 ||
                  section == 6,
              showLabel: expanded),
          if (expanded) ...[
            _SidebarItem(
                icon: Icons.inventory_2_rounded,
                label: 'Productos',
                active: section == 1,
                showLabel: true,
                nested: true,
                onTap: () => onSectionChanged(1)),
            _SidebarItem(
                icon: Icons.account_tree_rounded,
                label: 'Rubros y subrubros',
                active: section == 2,
                showLabel: true,
                nested: true,
                onTap: () => onSectionChanged(2)),
            _SidebarItem(
                icon: Icons.view_module_rounded,
                label: 'Sectores',
                active: section == 3,
                showLabel: true,
                nested: true,
                onTap: () => onSectionChanged(3)),
            _SidebarItem(
                icon: Icons.payments_outlined,
                label: 'Descuentos y pagos',
                active: section == 5,
                showLabel: true,
                nested: true,
                onTap: () => onSectionChanged(5)),
            _SidebarItem(
                icon: Icons.print_rounded,
                label: 'Impresoras',
                active: section == 6,
                showLabel: true,
                nested: true,
                onTap: () => onSectionChanged(6)),
          ] else
            _SidebarItem(
                icon: Icons.inventory_2_rounded,
                label: 'Productos',
                active: section == 1 ||
                    section == 2 ||
                    section == 3 ||
                    section == 5 ||
                    section == 6,
                showLabel: false,
                onTap: () => onSectionChanged(1)),
          _SidebarItem(
              icon: Icons.account_balance_wallet_rounded,
              label: 'Caja',
              active: false,
              showLabel: expanded),
          _SidebarItem(
              icon: Icons.bar_chart_rounded,
              label: 'Estadísticas',
              active: false,
              showLabel: expanded),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool showLabel;
  final VoidCallback? onTap;
  final bool nested;
  const _SidebarItem(
      {required this.icon,
      required this.label,
      required this.active,
      this.showLabel = true,
      this.onTap,
      this.nested = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: 2, left: nested ? 20 : 0),
      decoration: BoxDecoration(
        color: active ? Colors.white.withOpacity(0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Tooltip(
        message: showLabel ? '' : label,
        child: ListTile(
          onTap: onTap,
          dense: true,
          leading: Icon(
            icon,
            color: active ? Colors.white : Colors.white70,
            size: 18,
          ),
          title: showLabel
              ? Text(
                  label,
                  style: GoogleFonts.poppins(
                    color: active ? Colors.white : Colors.white70,
                    fontSize: 13,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  ),
                )
              : null,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

// ── Contenido ─────────────────────────────────────────────────────────────────
class _HomeContent extends StatefulWidget {
  final UserSession session;
  const _HomeContent({required this.session});

  @override
  State<_HomeContent> createState() => _HomeContentState();
}

class _HomeContentState extends State<_HomeContent> {
  late String? _imageUrl;
  bool _uploading = false;
  int _openTables = 0;
  int _totalTables = 0;

  String? _resolveUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    if (url.startsWith('http://') || url.startsWith('https://')) return url;
    return '${ApiConfig.baseUrl}$url';
  }

  @override
  void initState() {
    super.initState();
    final raw = widget.session.empresa.imagenUrl;
    _imageUrl = _resolveUrl(raw);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSalonSummary());
  }

  Future<void> _loadSalonSummary() async {
    try {
      final sectorProvider = context.read<SectorProvider>();
      final salesProvider = context.read<SalesProvider>();
      salesProvider.configure(
          token: widget.session.token, userId: widget.session.id);
      await sectorProvider.load(token: widget.session.token);
      final activeSales = await salesProvider.getActiveSales();
      if (!mounted) return;
      final occupiedIds = <int>{};
      for (final sale in activeSales) {
        occupiedIds.add(sale.tableId);
      }
      final allTables = sectorProvider.tables;
      setState(() {
        _totalTables = allTables.length;
        _openTables =
            allTables.where((table) => occupiedIds.contains(table.id)).length;
      });
    } catch (_) {
      if (!mounted) return;
      final allTables = context.read<SectorProvider>().tables;
      setState(() {
        _totalTables = allTables.length;
        _openTables = allTables
            .where((table) =>
                table.status.toLowerCase() != 'libre' &&
                table.status.toLowerCase() != 'cerrada')
            .length;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final empresa = widget.session.empresa;
    final isWide = MediaQuery.of(context).size.width >= 800;
    final providerTableCount = context.watch<SectorProvider>().tables.length;
    final totalTables =
        providerTableCount > 0 ? providerTableCount : _totalTables;

    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: isWide
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _LogoUpload(
                  imageUrl: _imageUrl,
                  onTap: _pickImage,
                  uploading: _uploading,
                  size: 160,
                ),
                const SizedBox(width: 36),
                Expanded(
                    child: _EmpresaInfo(
                        empresa: empresa,
                        sucursal: widget.session.sucursal,
                        openTables: _openTables,
                        totalTables: totalTables)),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _LogoUpload(
                  imageUrl: _imageUrl,
                  onTap: _pickImage,
                  uploading: _uploading,
                  size: 120,
                ),
                const SizedBox(height: 24),
                _EmpresaInfo(
                    empresa: empresa,
                    sucursal: widget.session.sucursal,
                    openTables: _openTables,
                    totalTables: totalTables),
              ],
            ),
    );
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _uploading = true);

    try {
      final empresaId = widget.session.idEmpresa;
      final uri = Uri.parse(
          ApiConfig.baseUrl + ApiConfig.uploadImageEndpoint(empresaId));

      final request = http.MultipartRequest('POST', uri)
        ..headers.addAll({
          ApiConfig.apiKeyHeader: ApiConfig.apiKeyValue,
        })
        ..files.add(http.MultipartFile.fromBytes(
          'Imagen',
          file.bytes!,
          filename: file.name,
        ));

      final response = await request.send().timeout(ApiConfig.timeout);
      final responseBody = await response.stream.bytesToString();

      // Log para debug
      debugPrint('Upload status: ${response.statusCode}');
      debugPrint('Upload body: $responseBody');

      if (!mounted) return;

      if (response.statusCode == 200 || response.statusCode == 204) {
        // Intentamos parsear la URL devuelta por la API
        String? newUrl;
        try {
          final json = jsonDecode(responseBody);
          final raw =
              json['data']?['imagenUrl'] ?? json['imagenUrl'] ?? json['data'];
          newUrl = _resolveUrl(raw?.toString());
        } catch (_) {}
        setState(() {
          _imageUrl = newUrl ??
              '${ApiConfig.baseUrl}/api/empresas/$empresaId/imagen?t=${DateTime.now().millisecondsSinceEpoch}';
        });
        _showSnack('Imagen actualizada correctamente', success: true);
      } else {
        _showSnack('Error ${response.statusCode}: $responseBody');
      }
    } catch (e) {
      if (mounted) _showSnack('No se pudo conectar al servidor');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: GoogleFonts.poppins(fontSize: 13)),
        backgroundColor:
            success ? const Color(0xFF10B981) : const Color(0xFF1A0A2E),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }
}

// ── Placeholder / imagen de empresa ──────────────────────────────────────────
class _LogoUpload extends StatelessWidget {
  final String? imageUrl;
  final VoidCallback onTap;
  final double size;
  final bool uploading;
  const _LogoUpload(
      {required this.imageUrl,
      required this.onTap,
      required this.size,
      this.uploading = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: const Color(0xFFF0EEF8),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFD6D0F0),
                width: 1.5,
              ),
            ),
            child: imageUrl != null && !uploading
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.network(
                      imageUrl!,
                      fit: BoxFit.contain,
                      headers: const {
                        ApiConfig.apiKeyHeader: ApiConfig.apiKeyValue
                      },
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Color(0xFFB0A8D8),
                        size: 40,
                      ),
                    ),
                  )
                : uploading
                    ? const Center(
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(0xFF6C5CE7),
                        ),
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            color: const Color(0xFFB0A8D8),
                            size: size * 0.28,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Subir logo',
                            style: GoogleFonts.poppins(
                              color: const Color(0xFFB0A8D8),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
          ),
          // Badge de edición
          Positioned(
            bottom: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xFFFF8C42),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.edit_rounded, color: Colors.white, size: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Datos de la empresa ───────────────────────────────────────────────────────
class _EmpresaInfo extends StatelessWidget {
  final dynamic empresa;
  final dynamic sucursal;
  final int openTables;
  final int totalTables;
  const _EmpresaInfo({
    required this.empresa,
    required this.sucursal,
    required this.openTables,
    required this.totalTables,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          empresa.nombre,
          style: GoogleFonts.poppins(
            color: const Color(0xFF2D2260),
            fontSize: 28,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        const SizedBox(height: 18),
        _SalonSummary(openTables: openTables, totalTables: totalTables),
        const SizedBox(height: 16),
        _DataChip(
          icon: Icons.location_on_outlined,
          text: sucursal.direccion,
        ),
        const SizedBox(height: 8),
        _DataChip(
          icon: Icons.phone_outlined,
          text: empresa.telefono,
        ),
      ],
    );
  }
}

class _SalonSummary extends StatelessWidget {
  final int openTables;
  final int totalTables;

  const _SalonSummary({required this.openTables, required this.totalTables});

  @override
  Widget build(BuildContext context) {
    final freeTables = (totalTables - openTables).clamp(0, totalTables);
    final occupation = totalTables == 0 ? 0 : (openTables * 100 / totalTables);
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _SalonMetric(
          icon: Icons.table_restaurant_rounded,
          label: 'Mesas abiertas',
          value: '$openTables',
          color: const Color(0xFFF0A83A),
        ),
        _SalonMetric(
          icon: Icons.event_seat_outlined,
          label: 'Mesas libres',
          value: '$freeTables',
          color: const Color(0xFF59A86A),
        ),
        _SalonMetric(
          icon: Icons.donut_small_rounded,
          label: 'Ocupación',
          value: '${occupation.round()}%',
          color: const Color(0xFF6C5CE7),
        ),
      ],
    );
  }
}

class _SalonMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _SalonMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 155),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(.09),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(.28)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: GoogleFonts.poppins(
                    color: const Color(0xFF6B6589), fontSize: 11)),
            Text(value,
                style: GoogleFonts.poppins(
                    color: const Color(0xFF2D2260),
                    fontSize: 19,
                    fontWeight: FontWeight.w800)),
          ]),
        ]),
      );
}

// ── Chip de dato ──────────────────────────────────────────────────────────────
class _DataChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _DataChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: const Color(0xFF6C5CE7), size: 16),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            text,
            style: GoogleFonts.poppins(
              color: const Color(0xFF6B6589),
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
