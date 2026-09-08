import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../models/user_session.dart';

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

  /// Intenta restaurar la sesión guardada. Llamar al arrancar la app.
  Future<bool> tryRestoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kSessionKey);
      if (raw != null) {
        final restored =
            UserSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (_tokenExpired(restored.token)) {
          await prefs.remove(_kSessionKey);
          _session = null;
          _status = AuthStatus.idle;
          notifyListeners();
          return false;
        }
        _session = restored;
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

  Future<void> _clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSessionKey);
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

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final codigo = body['codigo'] as int;

      if (response.statusCode == 200 && codigo == 200) {
        _session = UserSession.fromJson(body['data'] as Map<String, dynamic>);
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
