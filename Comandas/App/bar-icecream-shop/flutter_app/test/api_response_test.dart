import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:bar_icecream_shop/utils/api_response.dart';

void main() {
  test('decodes normal API responses', () {
    expect(decodeApiResponse(http.Response('{"data":[]}', 200))['data'], []);
  });

  test('preserves API error details', () {
    expect(
        decodeApiResponse(http.Response('{"error":"Sin stock"}', 400))['error'],
        'Sin stock');
  });

  test('handles empty, HTML and truncated server errors', () {
    for (final body in [
      '',
      '  ',
      '<html>Error</html>',
      '{"error":',
      'null',
      '[]'
    ]) {
      expect(decodeApiResponse(http.Response(body, 500))['error'],
          contains('500'));
    }
  });

  test('empty unauthorized response asks for login', () {
    expect(decodeApiResponse(http.Response('', 401))['error'],
        contains('iniciar sesión'));
  });

  test('rejects malformed successful responses with a readable error', () {
    for (final body in ['', ' ', '<html>', '{', 'null', '[]']) {
      expect(
          () => decodeApiResponse(http.Response(body, 200)),
          throwsA(predicate((e) =>
              e is Exception &&
              e is! FormatException &&
              e.toString().contains('respuesta vacía o inválida'))));
    }
  });

  test('accepts no-content responses', () {
    expect(decodeApiResponse(http.Response('', 204)), isEmpty);
  });
}
