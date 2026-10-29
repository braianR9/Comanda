import 'dart:typed_data';
import 'dart:async';
import '../../utils/excel_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../providers/product_provider.dart';

class ProductImportDialog extends StatefulWidget {
  final ProductProvider provider;
  const ProductImportDialog({super.key, required this.provider});

  @override
  State<ProductImportDialog> createState() => _ProductImportDialogState();
}

class _ProductImportDialogState extends State<ProductImportDialog> {
  Uint8List? _bytes;
  String _name = '';
  Map<String, dynamic>? _preview;
  String? _error;
  bool _busy = false;
  bool _done = false;
  bool _downloadingTemplate = false;
  String _status = '';
  final _elapsed = Stopwatch();
  final _stageElapsed = Stopwatch();
  Timer? _progressTimer;
  Completer<void>? _selectionCancellation;
  String _stage = '';
  int _processed = 0;
  int _total = 0;

  @override
  void dispose() {
    _cancelSelection();
    _progressTimer?.cancel();
    _elapsed.stop();
    _stageElapsed.stop();
    super.dispose();
  }

  void _cancelSelection() {
    final selection = _selectionCancellation;
    if (selection != null && !selection.isCompleted) selection.complete();
  }

  void _startProgress() {
    _progressTimer?.cancel();
    _elapsed
      ..reset()
      ..start();
    _stageElapsed
      ..reset()
      ..start();
    _stage = '';
    _processed = 0;
    _total = 0;
    _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  void _stopProgress() {
    _progressTimer?.cancel();
    _elapsed.stop();
    _stageElapsed.stop();
  }

  void _onProgress(Map<String, dynamic> event) {
    if (!mounted) return;
    final stage = event['etapa'] as String? ?? '';
    setState(() {
      if (_stage != stage) {
        _stageElapsed
          ..reset()
          ..start();
      }
      _stage = stage;
      _processed = (event['procesados'] as num?)?.toInt() ?? 0;
      _total = (event['total'] as num?)?.toInt() ?? 0;
      _status = switch (stage) {
        'envio' => 'Enviando el Excel al servidor…',
        'lectura' => 'Leyendo el Excel…',
        'referencias' => 'Buscando productos existentes, rubros y alícuotas…',
        'validacion' => 'Validando productos',
        'guardado' => 'Procesando productos',
        'confirmacion' => 'Confirmando los cambios…',
        'catalogo' => 'Actualizando el listado de productos…',
        _ => 'Preparando importación…',
      };
    });
  }

  String _duration(int seconds) =>
      seconds < 60 ? '$seconds s' : '${seconds ~/ 60} min ${seconds % 60} s';

  String? get _remainingTime {
    if (_stage != 'guardado' ||
        _processed < 3 ||
        _processed >= _total ||
        _stageElapsed.elapsedMilliseconds < 1000) {
      return null;
    }
    final remaining = (_stageElapsed.elapsedMilliseconds /
            _processed *
            (_total - _processed) /
            1000)
        .ceil();
    return 'Restante estimado: ${_duration(remaining)} + confirmación';
  }

  Future<void> _downloadTemplate() async {
    setState(() => _downloadingTemplate = true);
    try {
      final data = await rootBundle
          .load('assets/templates/plantilla_productos_focobr.xlsx');
      final saved = await FilePicker.saveFile(
        dialogTitle: 'Guardar plantilla de productos',
        fileName: 'plantilla_productos_focobr.xlsx',
        bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
      );
      if (!mounted || (!kIsWeb && saved == null)) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Plantilla lista. Completá la hoja Productos y luego seleccioná el archivo para importar.'),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'No se pudo descargar la plantilla: ${e.toString().replaceFirst('Exception: ', '')}'),
      ));
    } finally {
      if (mounted) setState(() => _downloadingTemplate = false);
    }
  }

  Future<void> _pick() async {
    _startProgress();
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Seleccioná un archivo Excel…';
      _stage = 'seleccion';
    });
    final selection = Completer<void>();
    _selectionCancellation = selection;
    try {
      final file = await pickProductExcel(cancel: selection.future);
      if (file == null) {
        if (mounted) {
          setState(() => _status = 'No se seleccionó ningún archivo.');
        }
        return;
      }
      if (!mounted) return;
      _startProgress();
      setState(() {
        _stage = 'archivo';
        _status = 'Leyendo el archivo…';
      });
      if (file.size != null && file.size! > 5 * 1024 * 1024) {
        throw Exception('Seleccione un Excel de hasta 5 MB.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.length > 5 * 1024 * 1024) {
        throw Exception('Seleccione un Excel de hasta 5 MB.');
      }
      _bytes = bytes;
      _name = file.name;
      setState(() {
        _preview = null;
        _status = 'Validando el Excel con el servidor…';
      });
      final result = await widget.provider
          .importWorkbook(_bytes!, _name, onProgress: _onProgress);
      if (mounted) {
        setState(() {
          _preview = result;
          _status = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      _selectionCancellation = null;
      _stopProgress();
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _confirm() async {
    _startProgress();
    setState(() {
      _busy = true;
      _error = null;
      _status = 'Guardando productos…';
    });
    try {
      final result = await widget.provider.importWorkbook(_bytes!, _name,
          confirm: true, onProgress: _onProgress);
      if (mounted) {
        setState(() {
          _preview = result;
          _done = result['puedeImportar'] == true;
          _status = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    } finally {
      _stopProgress();
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = (_preview?['filas'] as List?) ?? [];
    final omitted = (_preview?['omitidos'] as num?)?.toInt() ?? 0;
    final invalid = rows
        .where((row) => (row['errores'] as List? ?? []).isNotEmpty)
        .toList();
    final displayedRows = [
      ...invalid,
      ...rows.where((row) => (row['errores'] as List? ?? []).isEmpty)
    ];
    final String? blockedReason = _preview == null
        ? (_busy
            ? null
            : 'Seleccioná un Excel y esperá la vista previa para confirmar.')
        : invalid.isNotEmpty
            ? '${invalid.length} filas con errores. Fila ${invalid.first['fila']}: ${(invalid.first['errores'] as List).first}'
            : rows.isEmpty
                ? 'El archivo no contiene productos para importar.'
                : rows.length <= omitted
                    ? 'Todos los productos ya existen: no hay productos nuevos para importar.'
                    : _preview!['puedeImportar'] != true
                        ? 'El servidor no habilitó la importación. Actualizá la API y volvé a seleccionar el archivo.'
                        : null;
    return PopScope(
      canPop: !_busy || _stage == 'seleccion',
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _cancelSelection();
      },
      child: AlertDialog(
        title: const Text('Importar productos desde Excel'),
        content: SizedBox(
          width: 760,
          height: 470,
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  const Text(
                      'Completá la plantilla o usá el exportado de Productos con Código, Nombre, Costo, Precio, Rubro, Subrubro, Alicuota y Activo. Se crean rubros y subrubros faltantes. Los existentes por código importado o nombre se omiten.'),
                  const SizedBox(height: 8),
                  const Text(
                      'Se asignan códigos internos nuevos y se conserva el código del Excel como referencia. Stock, imágenes y componentes quedan sin configurar. La visibilidad en salón, delivery y carta queda desactivada hasta que la configures.'),
                  const SizedBox(height: 12),
                  if (!_done)
                    Wrap(spacing: 12, runSpacing: 8, children: [
                      OutlinedButton.icon(
                        onPressed: _busy || _downloadingTemplate
                            ? null
                            : _downloadTemplate,
                        icon: const Icon(Icons.download_outlined),
                        label: Text(_downloadingTemplate
                            ? 'Preparando plantilla…'
                            : 'Descargar plantilla Excel'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _busy || _downloadingTemplate ? null : _pick,
                        icon: const Icon(Icons.upload_file),
                        label:
                            Text(_name.isEmpty ? 'Seleccionar Excel' : _name),
                      ),
                    ]),
                  if (!_done) ...[
                    const SizedBox(height: 8),
                    const Text(
                        'Completá la hoja Productos. La plantilla incluye instrucciones y ejemplos en hojas separadas. Máximo 2000 productos y 5 MB por archivo.'),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: (_stage == 'guardado' || _stage == 'validacion') &&
                              _total > 0
                          ? _processed / _total
                          : null,
                    ),
                    const SizedBox(height: 6),
                    Text(_total > 0 &&
                            (_stage == 'guardado' || _stage == 'validacion')
                        ? '$_status: $_processed de $_total · ${(_processed * 100 / _total).floor()}%'
                        : _status),
                    if (_elapsed.isRunning)
                      Text(
                          'Transcurrido: ${_duration(_elapsed.elapsed.inSeconds)}'
                          '${_remainingTime == null ? '' : ' · $_remainingTime'}'),
                    if (_stage == 'guardado' || _stage == 'confirmacion')
                      const Text(
                          'Los productos se guardan al terminar la confirmación.'),
                    if (_elapsed.elapsed.inSeconds >= 30 &&
                        const {
                          'envio',
                          'lectura',
                          'referencias',
                          'validacion',
                          'confirmacion',
                          'catalogo'
                        }.contains(_stage))
                      const Text(
                          'Está tardando más de lo habitual. Esperando respuesta del servidor…'),
                  ],
                  if (_busy &&
                      _stage == 'seleccion' &&
                      _elapsed.elapsed.inSeconds >= 15)
                    Wrap(
                        spacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Text(
                              'Todavía no se recibió un archivo. Podés cancelar y volver a seleccionarlo.'),
                          TextButton(
                              onPressed: _cancelSelection,
                              child: const Text('Detener selección')),
                        ]),
                  if (!_busy && _status.isNotEmpty && _error == null)
                    Text(_status),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  if (_preview != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_done
                          ? '${_preview!['importados']} importados · $omitted omitidos'
                          : '${rows.length} filas · ${rows.length - omitted} nuevos · $omitted omitidos'),
                    ),
                  if (!_done && blockedReason != null)
                    Text(blockedReason,
                        style: TextStyle(
                            color: invalid.isNotEmpty
                                ? Theme.of(context).colorScheme.error
                                : null)),
                ])),
            SliverList(
                delegate: SliverChildBuilderDelegate(
              (_, index) {
                final row = displayedRows[index] as Map<String, dynamic>;
                final errors = (row['errores'] as List? ?? []).cast<String>();
                final warnings =
                    (row['advertencias'] as List? ?? []).cast<String>();
                return ListTile(
                  dense: true,
                  leading: Icon(
                      errors.isNotEmpty
                          ? Icons.error_outline
                          : row['omitir'] == true
                              ? Icons.skip_next
                              : Icons.check_circle_outline,
                      color: errors.isNotEmpty
                          ? Theme.of(context).colorScheme.error
                          : null),
                  title: Text(
                      'Fila ${row['fila']} · ${row['codigo']} · ${row['nombre']}'),
                  subtitle: Text([
                    '${row['rubro']} / ${row['subrubro']} · Precio: ${row['precio']}',
                    ...errors,
                    ...warnings,
                  ].join('\n')),
                );
              },
              childCount: displayedRows.length,
            )),
          ]),
        ),
        actions: [
          TextButton(
              onPressed: !_busy || _stage == 'seleccion'
                  ? () {
                      _cancelSelection();
                      Navigator.pop(context);
                    }
                  : null,
              child: Text(_done ? 'Cerrar' : 'Cancelar')),
          if (!_done)
            FilledButton(
              onPressed: !_busy &&
                      _preview?['puedeImportar'] == true &&
                      rows.length > omitted
                  ? _confirm
                  : null,
              child: const Text('Confirmar importación'),
            ),
        ],
      ),
    );
  }
}
