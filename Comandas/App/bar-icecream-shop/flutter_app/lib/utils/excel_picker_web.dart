import 'dart:async';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'picked_excel.dart';

Future<PickedExcel?> pickProductExcel({Future<void>? cancel}) {
  final result = Completer<PickedExcel?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.xlsx'
    ..multiple = false
    ..setAttribute('data-product-excel-picker', '')
    ..style.position = 'fixed'
    ..style.left = '-10000px';
  late final JSFunction changeListener;
  late final JSFunction cancelListener;

  void cleanup() {
    input.removeEventListener('change', changeListener);
    input.removeEventListener('cancel', cancelListener);
    input.remove();
  }

  void cancelSelection() {
    if (result.isCompleted) return;
    cleanup();
    result.complete(null);
  }

  changeListener = ((web.Event event) {
    if (result.isCompleted) return;
    final file = input.files?.item(0);
    cleanup();
    result.complete(file == null
        ? null
        : PickedExcel(
            name: file.name,
            size: file.size,
            readAsBytes: () async =>
                (await file.arrayBuffer().toDart).toDart.asUint8List(),
          ));
  }).toJS;
  cancelListener = ((web.Event event) => cancelSelection()).toJS;
  input.addEventListener('change', changeListener);
  input.addEventListener('cancel', cancelListener);
  cancel?.then((_) => cancelSelection());

  // Keep the input attached until change/cancel. Removing it immediately after
  // click can prevent the browser from delivering the selected file.
  try {
    web.document.body!.appendChild(input);
    input.click();
  } catch (error, stack) {
    cleanup();
    result.completeError(error, stack);
  }
  return result.future;
}
