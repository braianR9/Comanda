import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Devuelve dónde quedó el archivo, o null si se canceló.
Future<String?> saveExcelFile(String fileName, Uint8List bytes,
    {String dialogTitle = 'Guardar archivo'}) async {
  final saved = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    bytes: bytes,
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
  );
  return saved?.toString();
}
