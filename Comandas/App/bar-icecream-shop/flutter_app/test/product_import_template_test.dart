import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focobr/providers/product_provider.dart';
import 'package:focobr/screens/products/product_import_dialog.dart';

class _SavePicker extends FilePickerPlatform {
  Uint8List? savedBytes;
  String? savedName;
  bool fail = false;
  @override
  Future<Uri?> saveFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileSaving,
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    if (fail) throw Exception('No se pudo guardar el archivo.');
    savedName = fileName;
    savedBytes = bytes;
    return Uri.file('/tmp/$fileName');
  }
}

class _Products extends ProductProvider {
  int imports = 0;
  @override
  Future<Map<String, dynamic>> importWorkbook(Uint8List bytes, String name,
      {bool confirm = false,
      void Function(Map<String, dynamic>)? onProgress}) async {
    imports++;
    throw StateError('Downloading a template must not import products.');
  }
}

void main() {
  late _SavePicker picker;
  late FilePickerPlatform previous;
  setUp(() {
    previous = FilePickerPlatform.instance;
    picker = _SavePicker();
    FilePickerPlatform.instance = picker;
  });
  tearDown(() => FilePickerPlatform.instance = previous);

  testWidgets('Downloads the real XLSX asset without selecting or importing it',
      (tester) async {
    final products = _Products();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProductImportDialog(provider: products))));
    await tester.tap(find.text('Descargar plantilla Excel'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(picker.savedName, 'plantilla_productos_focobr.xlsx');
    expect(
        picker.savedBytes?.take(2), [0x50, 0x4b]); // XLSX is a ZIP container.
    expect(products.imports, 0);
    expect(find.text('Seleccionar Excel'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Confirmar importación'))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Template controls remain usable in a narrow dialog',
      (tester) async {
    tester.view.physicalSize = const Size(390, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: ProductImportDialog(provider: _Products()))));
    await tester.ensureVisible(find.text('Descargar plantilla Excel'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    picker.fail = true;
    await tester.tap(find.text('Descargar plantilla Excel'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('No se pudo descargar la plantilla'),
        findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(
                OutlinedButton, 'Descargar plantilla Excel'))
            .onPressed,
        isNotNull);
    expect(tester.takeException(), isNull);
  });
}
