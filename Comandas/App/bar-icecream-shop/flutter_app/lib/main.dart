import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/auth_provider.dart';
import 'providers/product_provider.dart';
import 'providers/sector_provider.dart';
import 'providers/sales_provider.dart';
import 'providers/sales_catalogs_provider.dart';
import 'providers/stock_movement_provider.dart';
import 'providers/customer_provider.dart';
import 'providers/printer_provider.dart';
import 'providers/user_management_provider.dart';
import 'providers/sales_report_provider.dart';
import 'providers/google_sheet_provider.dart';
import 'providers/caja_provider.dart';
import 'providers/price_list_provider.dart';
import 'screens/system/system_admin_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/session_guard.dart';
import 'screens/home/home_screen.dart';
import 'theme/app_theme.dart';
import 'theme/brand_colors.dart';
import 'utils/client_diagnostics.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ClientDiagnostics.install();
  final brand = BrandProvider();
  await brand.restoreLast();
  runApp(BarApp(brand: brand));
}

final _navigatorKey = GlobalKey<NavigatorState>();

class BarApp extends StatelessWidget {
  final BrandProvider brand;
  const BarApp({super.key, required this.brand});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
        ChangeNotifierProvider(create: (_) => ProductProvider()),
        ChangeNotifierProvider(create: (_) => SectorProvider()),
        ChangeNotifierProvider(create: (_) => SalesProvider()),
        ChangeNotifierProvider(create: (_) => SalesCatalogsProvider()),
        ChangeNotifierProvider(create: (_) => StockMovementProvider()),
        ChangeNotifierProvider(create: (_) => CustomerProvider()),
        ChangeNotifierProvider(create: (_) => PrinterProvider()),
        ChangeNotifierProvider(create: (_) => UserManagementProvider()),
        ChangeNotifierProvider(create: (_) => SalesReportProvider()),
        ChangeNotifierProvider(create: (_) => GoogleSheetProvider()),
        ChangeNotifierProvider(create: (_) => CajaProvider()),
        ChangeNotifierProvider(create: (_) => PriceListProvider()),
        // Color de la sucursal: se aplica al iniciar sesión o cambiar de sucursal.
        ChangeNotifierProxyProvider<AuthProvider, BrandProvider>(
          create: (_) => brand,
          update: (_, auth, brand) => brand!..useSession(auth.session),
        ),
      ],
      child: Consumer<BrandProvider>(
        builder: (_, brand, __) => MaterialApp(
          title: 'foco',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          navigatorKey: _navigatorKey,
          // Cierre de sesión por inactividad (no desde el login).
          builder: (_, child) => SessionGuard(
              navigatorKey: _navigatorKey,
              child: child ?? const SizedBox.shrink()),
          home: const _AppEntry(),
        ),
      ),
    );
  }
}

/// Pantalla inicial: restaura sesión y redirige
class _AppEntry extends StatefulWidget {
  const _AppEntry();
  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final auth = context.read<AuthProvider>();
    await auth.tryRestoreSession();
    if (!mounted) return;
    // El acceso de sistemas no se muestra en el login: se entra por app.focobr.net/sistemas.
    if (_isSystemsEntry) {
      SessionGuard.disabled = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const SystemAdminScreen()),
      );
    } else if (auth.isAuthenticated) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  static bool get _isSystemsEntry {
    final segments = Uri.base.pathSegments.where((s) => s.isNotEmpty);
    return segments.isNotEmpty && segments.last.toLowerCase() == 'sistemas';
  }

  @override
  Widget build(BuildContext context) {
    // Pantalla de carga mientras se restaura sesión
    return const Scaffold(
      backgroundColor: Color(0xFF1F1B16),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFFB4502B)),
      ),
    );
  }
}
