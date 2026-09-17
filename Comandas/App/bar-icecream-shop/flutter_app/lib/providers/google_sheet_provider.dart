import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

class GoogleSheetProvider extends ChangeNotifier {
  bool loading = false;
  String? error;
  String? sheetId;
  bool enabled = false;
  String? serviceAccountEmail;
  String _token = '';

  Map<String, String> get _headers => {
        ...ApiConfig.headers,
        if (_token.isNotEmpty) 'Authorization': 'Bearer $_token',
      };

  Future<void> load(String token) async {
    _token = token;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final data = _body(await http
          .get(Uri.parse('${ApiConfig.baseUrl}/api/sucursales/google-sheet'),
              headers: _headers)
          .timeout(ApiConfig.timeout))['data'] as Map<String, dynamic>?;
      sheetId = data?['sheetId']?.toString();
      enabled = data?['enabled'] as bool? ?? false;
      serviceAccountEmail = data?['serviceAccountEmail']?.toString();
    } catch (e) {
      error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> save(String token, String sheetIdOrUrl) async {
    _token = token;
    final data = _body(await http
        .put(Uri.parse('${ApiConfig.baseUrl}/api/sucursales/google-sheet'),
            headers: _headers, body: jsonEncode({'sheetIdOrUrl': sheetIdOrUrl}))
        .timeout(ApiConfig.timeout))['data'] as Map<String, dynamic>?;
    sheetId = data?['sheetId']?.toString();
    notifyListeners();
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
