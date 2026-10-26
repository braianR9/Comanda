import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import '../../config/api_config.dart';
import '../../utils/api_response.dart';

class PurchaseApi {
  final String token;
  PurchaseApi(this.token);
  Future<dynamic> call(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    final client = http.Client();
    try {
      final request = http.Request(
          method, Uri.parse('${ApiConfig.baseUrl}/api/$path'))
        ..headers
            .addAll({...ApiConfig.headers, 'Authorization': 'Bearer $token'});
      if (body != null) request.body = jsonEncode(body);
      final response = await client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(ApiConfig.timeout);
      final result = decodeApiResponse(response);
      if (response.statusCode >= 400) {
        final errors = result['errors'];
        throw Exception(result['error'] ??
            (errors is Map
                ? errors.values.expand((v) => v is List ? v : [v]).join('\n')
                : 'No se pudo guardar. Revisá los datos.'));
      }
      return result['data'];
    } on TimeoutException {
      throw Exception(
          'El servidor demoró demasiado. Actualizá antes de reintentar.');
    } finally {
      client.close();
    }
  }
}
