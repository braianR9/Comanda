import 'package:flutter/material.dart';
import '../purchases/purchase_api.dart';

class VoidSaleDialog extends StatefulWidget {
  final PurchaseApi api;
  final int saleId, saleNumber, version;
  final num total;
  const VoidSaleDialog(
      {super.key,
      required this.api,
      required this.saleId,
      required this.saleNumber,
      required this.version,
      required this.total});
  @override
  State<VoidSaleDialog> createState() => _VoidSaleDialogState();
}

class _VoidSaleDialogState extends State<VoidSaleDialog> {
  final _reason = TextEditingController();
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (_busy) return;
    final reason = _reason.text.trim();
    if (reason.length < 3) {
      setState(() =>
          _error = 'Indicá el motivo de la anulación (mínimo 3 caracteres).');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.call('sales/${widget.saleId}/void',
          method: 'POST', body: {'reason': reason, 'version': widget.version});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_busy,
        child: AlertDialog(
          title: Text('Anular venta N.º ${widget.saleNumber}'),
          content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                  child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      'Se anulará la venta y se registrará la devolución de \$${widget.total.toStringAsFixed(2)} por los medios de pago originales en la caja abierta.'),
                  const SizedBox(height: 8),
                  const Text(
                      'Se repondrá el stock descontado, incluidos los componentes de combos. La operación quedará en el historial con tu usuario y el motivo. No se puede deshacer.'),
                  const SizedBox(height: 16),
                  TextField(
                      controller: _reason,
                      enabled: !_busy,
                      autofocus: true,
                      maxLength: 500,
                      minLines: 2,
                      maxLines: 4,
                      decoration: const InputDecoration(
                          labelText: 'Motivo (obligatorio)')),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                ],
              ))),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: _busy ? null : _confirm,
                child: Text(_busy ? 'Anulando…' : 'Anular venta')),
          ],
        ),
      );
}
