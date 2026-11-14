import '../utils/api_response.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user_session.dart';
import '../utils/client_diagnostics.dart';
import '../utils/session_token.dart';

enum AuthStatus { idle, loading, authenticated, error }

class AuthProvider extends ChangeNotifier {
  AuthStatus _status = AuthStatus.idle;
  String? _errorMessage;
  UserSession? _session;

  AuthStatus get status => _status;
  String? get errorMessage => _errorMessage;
  UserSession? get session => _session;
  bool get isLoading => _status == AuthStatus.loading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  static const _kSessionKey = 'foco_session';
  static const _kActivityKey = 'foco_last_activity';

  /// Tiempo sin tocar el sistema hasta preguntar si se sigue usando.
  static const idleLimit = Duration(minutes: 30);

  /// Margen para responder "¿Seguís ahí?" antes de cerrar la sesión.
  static const idleWarning = Duration(seconds: 60);

  /// Momento en que se obtuvo el token actual (null: restaurado, se renueva al primer uso).
  DateTime? _tokenObtainedAt;
  DateTime _lastActivitySaved = DateTime.fromMillisecondsSinceEpoch(0);
  Future<bool>? _renewing;

  void _useToken(String token) {
    ClientDiagnostics.token = token;
    SessionToken.current = token;
  }

  /// Intenta restaurar la sesión guardada. Llamar al arrancar la app.
  Future<bool> tryRestoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSessionKey);
      if (raw != null) {
        final restored =
            UserSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        final lastActivity = prefs.getInt(_kActivityKey);
        final idle = lastActivity != null &&
            DateTime.now().difference(
                    DateTime.fromMillisecondsSinceEpoch(lastActivity)) >=
                idleLimit + idleWarning;
        if (idle || _tokenExpired(restored.token)) {
          await prefs.remove(_kSessionKey);
          _session = null;
          _status = AuthStatus.idle;
          notifyListeners();
          return false;
        }
        _session = restored;
        _tokenObtainedAt = null;
        _useToken(restored.token);
        _status = AuthStatus.authenticated;
        notifyListeners();
        return true;
      }
    } catch (e) {
      debugPrint('Restore session error: $e');
    }
    return false;
  }

  bool _tokenExpired(String token) {
    if (token.trim().isEmpty) return true;
    try {
      final rawToken =
          token.replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '');
      final parts = rawToken.split('.');
      if (parts.length != 3) return true;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      if (payload['session_stamp'] is! String) return true;
      final expiresAt = (payload['exp'] as num?)?.toInt();
      if (expiresAt == null) return true;
      return DateTime.now().millisecondsSinceEpoch ~/ 1000 >= expiresAt - 30;
    } catch (_) {
      return true;
    }
  }

  Future<void> _saveSession(UserSession s) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSessionKey, jsonEncode(s.toJson()));
  }

  Future<void> updateCompany(Map<String, dynamic> company, String token) async {
    final current = _session;
    if (current == null ||
        current.token != token ||
        company['id'] != current.idEmpresa) return;
    _session = UserSession.fromJson({...current.toJson(), 'empresa': company});
    notifyListeners();
    await _saveSession(_session!);
  }

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionKey);
    await prefs.remove(_kActivityKey);
  }

  /// Vencimiento del token actual, o null si no se puede leer.
  DateTime? get tokenExpiresAt {
    final token = _session?.token;
    if (token == null) return null;
    try {
      final payload = jsonDecode(utf8.decode(
              base64Url.decode(base64Url.normalize(token.split('.')[1]))))
          as Map<String, dynamic>;
      final exp = (payload['exp'] as num?)?.toInt();
      return exp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exp * 1000);
    } catch (_) {
      return null;
    }
  }

  /// Guarda la última actividad (como mucho una vez por minuto) para que, al
  /// reabrir la app después de un rato largo sin uso, se pida login de nuevo.
  /// Si el token tiene más de 5 minutos, lo renueva. Devuelve false si la
  /// sesión ya no es válida.
  Future<bool> markActivity({bool force = false}) async {
    if (_session == null) return false;
    final now = DateTime.now();
    if (force || now.difference(_lastActivitySaved).inSeconds >= 60) {
      _lastActivitySaved = now;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt(_kActivityKey, now.millisecondsSinceEpoch);
      } catch (_) {}
    }
    final obtained = _tokenObtainedAt;
    if (obtained == null || now.difference(obtained).inMinutes >= 5) {
      return renewToken();
    }
    return true;
  }

  /// Pide un token nuevo a la API. Devuelve false si la sesión ya no es válida
  /// (venció, el usuario fue desactivado o cambió la contraseña); en ese caso
  /// quien llama debe cerrar la sesión. Si no hay conexión devuelve true y
  /// se reintenta con la próxima actividad.
  Future<bool> renewToken() => _renewing ??= _renew().whenComplete(() => _renewing = null);

  Future<bool> _renew() async {
    final current = _session;
    if (current == null) return false;
    try {
      final response = await http
          .post(Uri.parse('${ApiConfig.baseUrl}/api/Auth/renovar'),
              headers: {
                ...ApiConfig.headers,
                'Authorization': 'Bearer ${current.token}'
              })
          .timeout(ApiConfig.timeout);
      if (response.statusCode == 401) return false;
      if (response.statusCode != 200) return true;
      final token = (decodeApiResponse(response)['data'] as Map?)?['token'];
      if (token is! String || _session?.token != current.token) return true;
      _session = UserSession.fromJson({...current.toJson(), 'token': token});
      _tokenObtainedAt = DateTime.now();
      _useToken(token);
      await _saveSession(_session!);
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Renew session error: $e');
      return true;
    }
  }

  Future<void> login({required String email, required String password}) async {
    _status = AuthStatus.loading;
    _errorMessage = null;
    notifyListeners();

    try {
      final uri = Uri.parse(ApiConfig.baseUrl + ApiConfig.loginEndpoint);
      final response = await http
          .post(
            uri,
            headers: ApiConfig.headers,
            body: jsonEncode({'email': email, 'password': password}),
          )
          .timeout(ApiConfig.timeout);

      final body = decodeApiResponse(response);
      final codigo = body['codigo'] as int?;

      if (response.statusCode == 200 && codigo == 200) {
        _session = UserSession.fromJson(body['data'] as Map<String, dynamic>);
        _tokenObtainedAt = DateTime.now();
        _useToken(_session!.token);
        await markActivity(force: true);
        _status = AuthStatus.authenticated;
        await _saveSession(_session!);
      } else {
        final error = body['error'];
        _errorMessage = (error is String && error.isNotEmpty)
            ? error
            : 'Email o contrasena incorrectos.';
        _status = AuthStatus.error;
      }
    } on http.ClientException {
      _errorMessage = 'No se pudo conectar al servidor.';
      _status = AuthStatus.error;
    } catch (e) {
      _errorMessage = 'Ocurrio un error inesperado.';
      _status = AuthStatus.error;
      debugPrint('Login error: $e');
    }

    notifyListeners();
  }

  void logout() {
    ClientDiagnostics.token = null;
    SessionToken.current = null;
    _tokenObtainedAt = null;
    _clearSession();
    _status = AuthStatus.idle;
    _session = null;
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    if (_status == AuthStatus.error) _status = AuthStatus.idle;
    notifyListeners();
  }
}
