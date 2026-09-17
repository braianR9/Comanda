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
import '../users/users_screen.dart';
import '../reports/sales_report_screen.dart';
import '../settings/google_sheet_settings_screen.dart';

/// Secciones visibles según el rol de la sesión.
/// 0 Inicio · 1 Productos · 2 Rubros · 3 Sectores · 4 Salón · 5 Descuentos y
/// pagos · 6 Impresoras · 7 Movimientos de stock · 8 Clientes · 9 Usuarios ·
/// 10 Listado de ventas · 11 Google Sheets.
Set<int> _allowedSections(UserSession session) => {
      0,
      4, 7, 8, // Ventas: todos los roles.
      if (session.canAccessMasters) ...{1, 2, 3, 5, 6, 10},
      if (session.canManageUsers) ...{9, 11},
    };

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AuthProvider>().session;
    if (session == null) return const SizedBox.shrink();
    return Scaffold(
      body: Stack(
        children: [
          const _HomeBg(),
          SafeArea(
            child: _WideLayout(session: session),
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
  final int section;
  final ValueChanged<int> onSelected;
  const _TopBar(
      {required this.isWide,
      required this.session,
      required this.section,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isWide ? 24 : 12, vertical: 10),
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
          const SizedBox(width: 16),
          Expanded(
              child: _MainMenu(
                  session: session, section: section, onSelected: onSelected)),
          const SizedBox(width: 12),
          if (MediaQuery.of(context).size.width >= 1200) ...[
            const Icon(Icons.location_on_outlined,
                color: Color(0xFF9E8FCC), size: 14),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(session.sucursal.nombre,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                      color: const Color(0xFF9E8FCC), fontSize: 13)),
            ),
            const SizedBox(width: 20),
          ],
          _UserChip(session: session, compact: !isWide),
        ],
      ),
    );
  }
}

// ── Chip de usuario ───────────────────────────────────────────────────────────
class _UserChip extends StatelessWidget {
  final UserSession session;
  final bool compact;
  const _UserChip({required this.session, this.compact = false});

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
            if (!compact) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 130,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      session.nombreCompleto,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF9E8FCC), size: 16),
            ],
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

  void _selectSection(int value) {
    if (value == _section) return;
    if (!_allowedSections(widget.session).contains(value)) return;
    setState(() {
      _section = value;
      if (value != 1) {
        _productEditorOpen = false;
        _editingProduct = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= 800;
    return Column(children: [
      _TopBar(
          isWide: isWide,
          session: widget.session,
          section: _section,
          onSelected: _selectSection),
      Expanded(
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sidebar + botón toggle superpuesto
          if (isWide)
            AnimatedBuilder(
              animation: _widthAnim,
              builder: (_, __) {
                final showLabel = _widthAnim.value > 0.5;
                final w = _WideLayoutState._kCollapsed +
                    (_WideLayoutState._kExpanded -
                            _WideLayoutState._kCollapsed) *
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
                          session: widget.session,
                          widthFactor: _widthAnim.value,
                          expanded: showLabel,
                          section: _section,
                          onSectionChanged: _selectSection,
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
                                      border: Border.all(
                                          color: Colors.white, width: 2),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.15),
                                          blurRadius: 6,
                                        ),
                                      ],
                                    ),
                                    child: AnimatedRotation(
                                      turns: _expanded ? 0 : 0.5,
                                      duration:
                                          const Duration(milliseconds: 220),
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
            child: _section == 11
                ? const GoogleSheetSettingsScreen(embedded: true)
                : _section == 10
                    ? const SalesReportScreen(embedded: true)
                    : _section == 9
                        ? const UsersScreen(embedded: true)
                        : _section == 8
                            ? const ClientsScreen(embedded: true)
                            : _section == 7
                                ? const StockMovementsScreen(embedded: true)
                                : _section == 6
                                    ? const PrintersScreen(embedded: true)
                                    : _section == 5
                                        ? const SalesCatalogsScreen(
                                            embedded: true)
                                        : _section == 4
                                            ? const SalesScreen(embedded: true)
                                            : _section == 1
                                                ? _productEditorOpen
                                                    ? ProductEditorScreen(
                                                        key: ValueKey(
                                                            _editingProduct
                                                                    ?.id ??
                                                                'new-product'),
                                                        product:
                                                            _editingProduct,
                                                        embedded: true,
                                                        onCancel: () =>
                                                            setState(() {
                                                          _productEditorOpen =
                                                              false;
                                                          _editingProduct =
                                                              null;
                                                        }),
                                                        onSaved:
                                                            (product) async {
                                                          try {
                                                            await context
                                                                .read<
                                                                    ProductProvider>()
                                                                .save(product);
                                                            if (!mounted)
                                                              return;
                                                            setState(() {
                                                              _productEditorOpen =
                                                                  false;
                                                              _editingProduct =
                                                                  null;
                                                            });
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(
                                                              const SnackBar(
                                                                  content: Text(
                                                                      'Producto guardado correctamente')),
                                                            );
                                                          } catch (error) {
                                                            if (!mounted)
                                                              return;
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(
                                                              SnackBar(
                                                                content: Text(error
                                                                    .toString()
                                                                    .replaceFirst(
                                                                        'Exception: ',
                                                                        '')),
                                                              ),
                                                            );
                                                          }
                                                        },
                                                      )
                                                    : ProductsScreen(
                                                        embedded: true,
                                                        onOpenEditor:
                                                            (product) =>
                                                                setState(() {
                                                          _editingProduct =
                                                              product;
                                                          _productEditorOpen =
                                                              true;
                                                        }),
                                                      )
                                                : _section == 2
                                                    ? const ProductGroupsScreen(
                                                        embedded: true)
                                                    : _section == 3
                                                        ? const SectorsScreen(
                                                            embedded: true)
                                                        : SingleChildScrollView(
                                                            padding:
                                                                const EdgeInsets
                                                                    .all(32),
                                                            child: _HomeContent(
                                                                session: widget
                                                                    .session),
                                                          ),
          ),
        ],
      )),
    ]);
  }
}

class _MainMenu extends StatelessWidget {
  final UserSession session;
  final int section;
  final ValueChanged<int> onSelected;
  const _MainMenu(
      {required this.session, required this.section, required this.onSelected});

  static const sales = <int, String>{
    4: 'Salón',
    7: 'Movimientos de stock',
    8: 'Clientes',
  };
  static const masters = <int, String>{
    1: 'Productos',
    2: 'Rubros y subrubros',
    3: 'Sectores',
    5: 'Descuentos y pagos',
    6: 'Impresoras',
  };
  static const statistics = <int, String>{
    10: 'Ventas · Listado de ventas',
  };

  Widget _group(String label, IconData icon, Map<int, String> entries) {
    final active = entries.containsKey(section);
    return PopupMenuButton<int>(
      tooltip: label,
      position: PopupMenuPosition.under,
      onSelected: onSelected,
      itemBuilder: (_) => entries.entries
          .map((entry) => PopupMenuItem<int>(
                value: entry.key,
                child: Row(children: [
                  Expanded(child: Text(entry.value)),
                  if (entry.key == section)
                    const Icon(Icons.check_rounded, size: 18),
                ]),
              ))
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEDE9FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 19, color: const Color(0xFF5C4D9B)),
          const SizedBox(width: 8),
          Text(label,
              style: TextStyle(
                  color: const Color(0xFF3D2D8A),
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500)),
          const SizedBox(width: 5),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        color: Colors.white,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          child: Row(children: [
            TextButton.icon(
                onPressed: () => onSelected(0),
                style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF3D2D8A),
                    backgroundColor:
                        section == 0 ? const Color(0xFFEDE9FF) : null,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 18)),
                icon: const Icon(Icons.home_rounded, size: 19),
                label: const Text('Inicio')),
            const SizedBox(width: 6),
            _group('Ventas', Icons.point_of_sale_rounded, sales),
            if (session.canAccessMasters) ...[
              const SizedBox(width: 6),
              _group('Maestros', Icons.school_rounded, masters),
            ],
            if (session.canAccessMasters) ...[
              const SizedBox(width: 6),
              _group('Estadísticas', Icons.bar_chart_rounded, statistics),
            ],
            if (session.canManageUsers) ...[
              const SizedBox(width: 6),
              TextButton.icon(
                  onPressed: () => onSelected(9),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF3D2D8A),
                      backgroundColor:
                          section == 9 ? const Color(0xFFEDE9FF) : null,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 18)),
                  icon: const Icon(Icons.badge_outlined, size: 19),
                  label: const Text('Usuarios')),
              const SizedBox(width: 6),
              TextButton.icon(
                  onPressed: () => onSelected(11),
                  style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFF3D2D8A),
                      backgroundColor:
                          section == 11 ? const Color(0xFFEDE9FF) : null,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 18)),
                  icon: const Icon(Icons.table_chart_outlined, size: 19),
                  label: const Text('Google Sheets')),
            ],
            const SizedBox(width: 6),
            const TextButton(onPressed: null, child: Text('Caja')),
          ]),
        ),
      );
}

// Accesos frecuentes; el menú completo está disponible en la barra superior.
class _Sidebar extends StatelessWidget {
  final UserSession session;
  final double widthFactor;
  final bool expanded;
  final int section;
  final ValueChanged<int> onSectionChanged;
  const _Sidebar({
    required this.session,
    this.widthFactor = 1,
    this.expanded = true,
    required this.section,
    required this.onSectionChanged,
  });

  @override
  Widget build(BuildContext context) => Container(
        width: _WideLayoutState._kCollapsed +
            (_WideLayoutState._kExpanded - _WideLayoutState._kCollapsed) *
                widthFactor,
        decoration: const BoxDecoration(
            color: Color(0xFF6C5CE7),
            border: Border(right: BorderSide(color: Color(0xFF5A4BD1)))),
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
          children: [
            if (expanded)
              const Padding(
                padding: EdgeInsets.fromLTRB(12, 0, 8, 16),
                child: Text('ACCESOS DIRECTOS',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ),
            _SidebarItem(
                icon: Icons.table_restaurant_rounded,
                label: 'Salón',
                active: section == 4,
                showLabel: expanded,
                onTap: () => onSectionChanged(4)),
            if (session.canAccessMasters)
              _SidebarItem(
                  icon: Icons.inventory_2_rounded,
                  label: 'Productos',
                  active: section == 1,
                  showLabel: expanded,
                  onTap: () => onSectionChanged(1)),
            _SidebarItem(
                icon: Icons.people_alt_rounded,
                label: 'Clientes',
                active: section == 8,
                showLabel: expanded,
                onTap: () => onSectionChanged(8)),
            _SidebarItem(
                icon: Icons.swap_vert_rounded,
                label: 'Movimientos de stock',
                active: section == 7,
                showLabel: expanded,
                onTap: () => onSectionChanged(7)),
          ],
        ),
      );
}

class _SidebarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool showLabel;
  final VoidCallback? onTap;
  const _SidebarItem(
      {required this.icon,
      required this.label,
      required this.active,
      this.showLabel = true,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
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
