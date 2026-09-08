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
import 'screens/auth/login_screen.dart';
import 'screens/home/home_screen.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const BarApp());
}

class BarApp extends StatelessWidget {
  const BarApp({super.key});

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
      ],
      child: MaterialApp(
        title: 'Foco',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        home: const _AppEntry(),
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
    if (auth.isAuthenticated) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pantalla de carga mientras se restaura sesión
    return const Scaffold(
      backgroundColor: Color(0xFF1A0A2E),
      body: Center(
        child: CircularProgressIndicator(color: Color(0xFFFF8C42)),
      ),
    );
  }
}
