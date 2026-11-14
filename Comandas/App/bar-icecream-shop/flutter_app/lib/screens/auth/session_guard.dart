import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import 'login_screen.dart';

/// Cierra la sesión por inactividad: si nadie toca el sistema durante
/// [AuthProvider.idleLimit], pregunta "¿Seguís ahí?" y, si no hay respuesta en
/// [AuthProvider.idleWarning], vuelve al login. Mientras se usa, la sesión se
/// renueva sola. Envuelve toda la app (MaterialApp.builder).
class SessionGuard extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  /// El panel de Sistemas tiene su propia sesión: ahí no se controla.
  static bool disabled = false;

  const SessionGuard(
      {super.key, required this.navigatorKey, required this.child});

  @override
  State<SessionGuard> createState() => _SessionGuardState();
}

class _SessionGuardState extends State<SessionGuard> {
  DateTime _lastActivity = DateTime.now();
  Timer? _timer;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _check());
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    _timer?.cancel();
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    _activity();
    return false;
  }

  bool get _active =>
      !SessionGuard.disabled && context.read<AuthProvider>().isAuthenticated;

  Future<void> _activity() async {
    // Mientras se muestra el aviso, solo cuentan sus botones.
    if (_asking || !_active) return;
    _lastActivity = DateTime.now();
    final valid = await context.read<AuthProvider>().markActivity();
    if (!valid && mounted && _active) _logout();
  }

  void _check() {
    if (_asking || !_active) {
      if (!_active) _lastActivity = DateTime.now();
      return;
    }
    final auth = context.read<AuthProvider>();
    final expires = auth.tokenExpiresAt;
    if (expires != null && DateTime.now().isAfter(expires)) {
      _logout();
    } else if (DateTime.now().difference(_lastActivity) >=
        AuthProvider.idleLimit) {
      _ask();
    }
  }

  Future<void> _ask() async {
    final navigatorContext = widget.navigatorKey.currentContext;
    if (navigatorContext == null) return;
    _asking = true;
    final keep = await showDialog<bool>(
      context: navigatorContext,
      barrierDismissible: false,
      builder: (_) => const _IdleDialog(),
    );
    _asking = false;
    if (!mounted || !_active) return;
    if (keep == true) {
      _lastActivity = DateTime.now();
      final auth = context.read<AuthProvider>();
      if (await auth.renewToken() && await auth.markActivity(force: true)) {
        return;
      }
    }
    _logout();
  }

  void _logout() {
    final navigator = widget.navigatorKey.currentState;
    context.read<AuthProvider>().logout();
    navigator?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (_) => _activity(),
        onPointerSignal: (_) => _activity(),
        child: widget.child,
      );
}

/// "¿Seguís ahí?" con cuenta regresiva: sin respuesta, se cierra la sesión.
class _IdleDialog extends StatefulWidget {
  const _IdleDialog();
  @override
  State<_IdleDialog> createState() => _IdleDialogState();
}

class _IdleDialogState extends State<_IdleDialog> {
  late int _seconds = AuthProvider.idleWarning.inSeconds;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_seconds <= 1) {
        _timer?.cancel();
        Navigator.of(context).pop(false);
      } else {
        setState(() => _seconds--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('¿Seguís ahí?'),
        content: Text(
            'No se usó el sistema en los últimos ${AuthProvider.idleLimit.inMinutes} minutos. '
            'Por seguridad, la sesión se va a cerrar en $_seconds segundos.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Salir')),
          FilledButton(
              autofocus: true,
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Seguir')),
        ],
      );
}
