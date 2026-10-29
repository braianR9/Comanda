import 'dart:async';
import 'dart:convert';

/// Reads newline-delimited events across arbitrary HTTP/UTF-8 chunk boundaries.
Future<Map<String, dynamic>> readProductImportEvents(
  Stream<List<int>> stream, {
  void Function(Map<String, dynamic>)? onProgress,
  Duration inactivityTimeout = const Duration(minutes: 2),
}) async {
  Map<String, dynamic>? result;
  await for (final line in stream
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .timeout(inactivityTimeout)) {
    if (line.trim().isEmpty) continue;
    final event = jsonDecode(line) as Map<String, dynamic>;
    if (event['tipo'] == 'error') throw Exception(event['error']);
    if (event['tipo'] == 'progreso') onProgress?.call(event);
    if (event['tipo'] == 'resultado') {
      result = event['data'] as Map<String, dynamic>;
    }
  }
  if (result == null) {
    throw Exception(
        'Se interrumpió la respuesta del servidor. Volvé a seleccionar el Excel para comprobar el resultado.');
  }
  return result;
}
