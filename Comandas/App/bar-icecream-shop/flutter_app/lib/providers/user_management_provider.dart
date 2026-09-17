import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/app_user.dart';

class UserManagementProvider extends ChangeNotifier {
  bool loading = false;
  String? error;
  List<AppUser> users = [];
  List<AppRole> roles = [];
  String _token = '';

  Map<String, String> get _headers => {
        ...ApiConfig.headers,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  Future<void> load(String token, {bool includeInactive = true}) async {
    _token = token;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/usuarios')
          .replace(queryParameters: {'includeInactive': '$includeInactive'});
      final data = _body(await http
              .get(uri, headers: _headers)
              .timeout(ApiConfig.timeout))['data'] as List? ??
          const [];
      users = [
        for (final item in data) AppUser.fromJson(item as Map<String, dynamic>)
      ];
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> loadRoles(String token) async {
    _token = token;
    final data = _body(await http
            .get(Uri.parse('${ApiConfig.baseUrl}/api/usuarios/roles'),
                headers: _headers)
            .timeout(ApiConfig.timeout))['data'] as List? ??
        const [];
    roles = [
      for (final item in data) AppRole.fromJson(item as Map<String, dynamic>)
    ];
    notifyListeners();
  }

  Future<void> save(AppUser user, {String? password}) async {
    final uri = Uri.parse(
        '${ApiConfig.baseUrl}/api/usuarios${user.id == 0 ? '' : '/${user.id}'}');
    final body = jsonEncode(user.toJson(password: password));
    final response = user.id == 0
        ? await http
            .post(uri, headers: _headers, body: body)
            .timeout(ApiConfig.timeout)
        : await http
            .put(uri, headers: _headers, body: body)
            .timeout(ApiConfig.timeout);
    _body(response);
    await load(_token);
  }

  Future<void> setActive(AppUser user, bool active) async {
    _body(await http
        .patch(Uri.parse('${ApiConfig.baseUrl}/api/usuarios/${user.id}/status'),
            headers: _headers, body: jsonEncode({'activo': active}))
        .timeout(ApiConfig.timeout));
    await load(_token);
  }

  Map<String, dynamic> _body(http.Response response) {
    final body = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(body['error']?.toString() ??
          body['title']?.toString() ??
          'Error del servidor (${response.statusCode}).');
    }
    return body;
  }
}
