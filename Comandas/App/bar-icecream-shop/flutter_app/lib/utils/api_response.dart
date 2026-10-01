import 'dart:convert';
import 'package:http/http.dart' as http;

/// Decode API objects without hiding HTTP errors behind JSON parser errors.
Map<String, dynamic> decodeApiResponse(http.Response response) {
  final failed = response.statusCode < 200 || response.statusCode >= 300;
  Map<String, dynamic>? body;
  if (response.body.trim().isNotEmpty) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } on FormatException {
      // Failed requests can return HTML, plain text, or truncated JSON.
    }
  }
  if (failed) {
    return body ??
        {
          'error': response.statusCode == 401
              ? 'La sesión venció. Volvé a iniciar sesión.'
              : 'Error del servidor (${response.statusCode}). Intentá nuevamente.',
        };
  }
  if (response.statusCode == 204) return body ?? {};
  if (body == null) {
    throw Exception('El servidor devolvió una respuesta vacía o inválida '
        '(HTTP ${response.statusCode}). Intentá nuevamente.');
  }
  return body;
}
