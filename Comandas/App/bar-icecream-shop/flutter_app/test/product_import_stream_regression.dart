// Standalone: dart run test/product_import_stream_regression.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:focobr/utils/product_import_stream.dart';

void check(bool value, String label) {
  if (!value) throw StateError(label);
  stdout.writeln('PASS: $label');
}

Future<void> main() async {
  final input = StreamController<List<int>>();
  final progress = <Map<String, dynamic>>[];
  var completed = false;
  final pending =
      readProductImportEvents(input.stream, onProgress: progress.add)
          .then((value) {
    completed = true;
    return value;
  });
  final line = '${jsonEncode({
        'tipo': 'progreso',
        'etapa': 'guardado',
        'procesados': 45,
        'total': 185
      })}\n';
  // One byte at a time: network packets do not follow event boundaries.
  for (final byte in utf8.encode(line)) {
    input.add([byte]);
  }
  await Future<void>.delayed(Duration.zero);
  check(progress.single['procesados'] == 45 && !completed,
      'Progress is delivered before import completion');
  input.add(utf8.encode('${jsonEncode({
        'tipo': 'progreso',
        'etapa': 'guardado',
        'procesados': 185,
        'total': 185
      })}\n'));
  await Future<void>.delayed(Duration.zero);
  check(!completed, '100% processed waits for the final result');
  final resultLine = utf8.encode('${jsonEncode({
        'tipo': 'resultado',
        'data': {'importados': 185, 'nombre': 'Café'}
      })}\n');
  for (final byte in resultLine) {
    input.add([byte]);
  }
  await input.close();
  check((await pending)['nombre'] == 'Café',
      'UTF-8 characters survive split packets');
  try {
    await readProductImportEvents(Stream.value(utf8.encode(line)));
    throw StateError('Incomplete import accepted');
  } on Exception catch (e) {
    check(e.toString().contains('interrumpió'),
        'Disconnected response never reports success');
  }
  try {
    await readProductImportEvents(Stream.value(utf8.encode('$line${jsonEncode({
          'tipo': 'error',
          'error': 'Error al confirmar'
        })}\n')));
    throw StateError('Server failure accepted');
  } on Exception catch (e) {
    check(e.toString().contains('Error al confirmar'),
        'Server errors propagate after progress');
  }
  final silent = StreamController<List<int>>();
  try {
    await readProductImportEvents(silent.stream,
        inactivityTimeout: const Duration(milliseconds: 10));
    throw StateError('Silent server did not time out');
  } on TimeoutException {
    stdout.writeln('PASS: Silent server times out');
  } finally {
    await silent.close();
  }
}
