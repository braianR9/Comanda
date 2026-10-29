import 'dart:typed_data';

class PickedExcel {
  final String name;
  final int? size;
  final Future<Uint8List> Function() readAsBytes;

  const PickedExcel({required this.name, required this.readAsBytes, this.size});
}
