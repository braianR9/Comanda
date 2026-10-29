// Compile with dart compile js, then load in a browser.
import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'package:web/web.dart' as web;
import 'package:focobr/utils/excel_picker_web.dart';

void check(bool value, String message) {
  if (!value) throw StateError(message);
}

web.HTMLInputElement input() =>
    web.document.querySelector('[data-product-excel-picker]')!
        as web.HTMLInputElement;

void selectFile(String name, String contents) {
  final transfer = web.DataTransfer();
  transfer.items.add(web.File([contents.toJS].toJS, name));
  input()
    ..files = transfer.files
    ..dispatchEvent(web.Event('change'));
}

Future<void> main() async {
  final output = web.document.querySelector('#result')!;
  try {
    var completed = false;
    final pending = pickProductExcel().then((file) {
      completed = true;
      return file;
    });
    check(input().isConnected,
        'Input must stay in the DOM while selection is pending');
    web.window.dispatchEvent(web.Event('focus'));
    await Future<void>.delayed(const Duration(milliseconds: 700));
    check(!completed, 'Browser focus must not cancel the selected file');
    selectFile('catalogo.xlsx', 'Excel bytes');
    final picked = await pending;
    check(
        picked?.name == 'catalogo.xlsx', 'Selected file must reach the caller');
    check(utf8.decode(await picked!.readAsBytes()) == 'Excel bytes',
        'Selected bytes must be readable');
    check(web.document.querySelector('[data-product-excel-picker]') == null,
        'Input removed after selection');
    final cancelled = pickProductExcel();
    input().dispatchEvent(web.Event('cancel'));
    check(
        await cancelled == null, 'Native cancellation completes the selection');
    final stop = Completer<void>();
    final stopped = pickProductExcel(cancel: stop.future);
    stop.complete();
    check(await stopped == null,
        'Manual cancellation releases the waiting caller');
    check(web.document.querySelector('[data-product-excel-picker]') == null,
        'Cancelled input removed');
    final retry = pickProductExcel();
    selectFile('catalogo.xlsx', 'Retry bytes');
    check(utf8.decode(await (await retry)!.readAsBytes()) == 'Retry bytes',
        'Same file can be selected after retry');
    output.textContent =
        'PASS: persistent input, delayed focus, file bytes, native cancel, manual cancel, retry';
  } catch (error, stack) {
    output.textContent = 'FAIL: $error\n$stack';
  }
}
