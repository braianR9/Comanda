import 'package:file_picker/file_picker.dart';
import 'picked_excel.dart';

Future<PickedExcel?> pickProductExcel({Future<void>? cancel}) async {
  final file = await Future.any([
    FilePicker.pickFile(
        type: FileType.custom, allowedExtensions: const ['xlsx']),
    if (cancel != null) cancel.then((_) => null),
  ]);
  if (file == null) return null;
  return PickedExcel(
      name: file.name, size: file.lengthSync(), readAsBytes: file.readAsBytes);
}
