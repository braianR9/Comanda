import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/invoice.dart';
import '../../providers/customer_provider.dart';
import '../purchases/purchase_api.dart';

/// Datos del receptor elegidos en el diálogo de facturación.
class InvoiceReceiver {
  final int? customerId;
  final String? documentType;
  final String? documentNumber;
  final String? name;
  const InvoiceReceiver(
      {this.customerId, this.documentType, this.documentNumber, this.name});
  static const finalConsumer = InvoiceReceiver();

  Map<String, dynamic> toJson() => {
        if (customerId != null) 'customerId': customerId,
        if (documentNumber != null) 'documentType': documentType,
        if (documentNumber != null) 'documentNumber': documentNumber,
        if (name != null && name!.isNotEmpty) 'name': name,
      };
}

Future<Invoice> invoiceSale(
    PurchaseApi api, int saleId, InvoiceReceiver receiver) async {
  final data = await api.call('sales/$saleId/facturar',
      method: 'POST', body: receiver.toJson());
  return Invoice.fromJson(Map<String, dynamic>.from(data));
}

/// Después de cobrar sale un solo comprobante: la factura o el ticket de pago.
/// Sin facturación lista, la API ya imprimió el ticket. Con facturación lista,
/// la impresión espera esta decisión (Facturar → factura; No facturar → ticket).
Future<void> offerInvoiceAfterCheckout(
    BuildContext context, String token, int saleId, int saleNumber) async {
  final api = PurchaseApi(token);
  final messenger = ScaffoldMessenger.of(context);
  Map<String, dynamic> config;
  try {
    config = Map<String, dynamic>.from(await api.call('facturacion/config'));
  } catch (_) {
    messenger.showSnackBar(const SnackBar(
        content: Text(
            'No se pudo consultar la facturación. Si no salió el ticket, imprimilo desde Comprobantes › Ventas sin facturar.')));
    return;
  }
  if (config['ready'] != true || !context.mounted) return;

  if (config['mode'] == 'Automatico') {
    var list = <Invoice>[];
    try {
      list = (await api.call('sales/$saleId/comprobantes') as List)
          .map((e) => Invoice.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      // Sin la lista se ofrece decidir igual, para que salga algún comprobante.
    }
    final ok = list.where((x) => x.authorized && !x.isCreditNote).lastOrNull;
    if (ok != null) {
      messenger.showSnackBar(SnackBar(
          content:
              Text('${ok.typeName} ${ok.number} autorizada · CAE ${ok.cae}')));
      return;
    }
    if (!context.mounted) return;
    final last = list.lastOrNull;
    await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => InvoiceDialog(
            api: api,
            saleId: saleId,
            printTicketOnSkip: true,
            title: 'No se pudo facturar la venta N.º $saleNumber',
            message: last?.messages.isNotEmpty == true
                ? last!.messages
                : 'AFIP no autorizó el comprobante. Podés reintentar ahora o más tarde desde Comprobantes.'));
    return;
  }
  await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => InvoiceDialog(
          api: api,
          saleId: saleId,
          printTicketOnSkip: true,
          title: '¿Facturar la venta N.º $saleNumber?'));
}

/// Elige el receptor (consumidor final, documento o cliente) y emite la factura.
class InvoiceDialog extends StatefulWidget {
  final PurchaseApi api;
  final int saleId;
  final String title;
  final String? message;

  /// Al cobrar: "No facturar" imprime el ticket de pago en lugar de la factura.
  final bool printTicketOnSkip;
  const InvoiceDialog(
      {super.key,
      required this.api,
      required this.saleId,
      required this.title,
      this.message,
      this.printTicketOnSkip = false});
  @override
  State<InvoiceDialog> createState() => _InvoiceDialogState();
}

class _InvoiceDialogState extends State<InvoiceDialog> {
  String _mode = 'final';
  String _docType = 'DNI';
  final _doc = TextEditingController(), _name = TextEditingController();
  Customer? _customer;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final customers = context.read<CustomerProvider>();
    if (customers.customers.isEmpty) customers.load(widget.api.token);
  }

  @override
  void dispose() {
    _doc.dispose();
    _name.dispose();
    super.dispose();
  }

  InvoiceReceiver? get _receiver => switch (_mode) {
        'document' => _doc.text.trim().isEmpty
            ? null
            : InvoiceReceiver(
                documentType: _docType,
                documentNumber: _doc.text.trim(),
                name: _name.text.trim()),
        'customer' =>
          _customer == null ? null : InvoiceReceiver(customerId: _customer!.id),
        _ => InvoiceReceiver.finalConsumer,
      };

  Future<void> _skip() async {
    if (!widget.printTicketOnSkip) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.api.call('sales/${widget.saleId}/ticket', method: 'POST');
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  Future<void> _issue() async {
    final receiver = _receiver;
    if (receiver == null) {
      setState(() => _error = _mode == 'customer'
          ? 'Elegí un cliente.'
          : 'Ingresá el número de documento.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final invoice = await invoiceSale(widget.api, widget.saleId, receiver);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${invoice.typeName} ${invoice.number} autorizada · CAE ${invoice.cae}')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.toString().replaceFirst('Exception: ', '');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final customers = context
        .watch<CustomerProvider>()
        .customers
        .where((c) => c.active)
        .toList();
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.message != null)
                  Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(widget.message!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                        value: 'final', label: Text('Consumidor final')),
                    ButtonSegment(
                        value: 'document', label: Text('Con DNI/CUIT')),
                    ButtonSegment(value: 'customer', label: Text('Cliente')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: _busy
                      ? null
                      : (value) => setState(() {
                            _mode = value.first;
                            _error = null;
                          }),
                ),
                const SizedBox(height: 16),
                if (_mode == 'document') ...[
                  Row(children: [
                    DropdownButton<String>(
                        value: _docType,
                        items: const [
                          DropdownMenuItem(value: 'DNI', child: Text('DNI')),
                          DropdownMenuItem(value: 'CUIT', child: Text('CUIT')),
                          DropdownMenuItem(value: 'CUIL', child: Text('CUIL')),
                        ],
                        onChanged: (v) => setState(() => _docType = v!)),
                    const SizedBox(width: 12),
                    Expanded(
                        child: TextField(
                            controller: _doc,
                            keyboardType: TextInputType.number,
                            decoration:
                                const InputDecoration(labelText: 'Número'))),
                  ]),
                  TextField(
                      controller: _name,
                      decoration: const InputDecoration(
                          labelText: 'Nombre (opcional)')),
                ],
                if (_mode == 'customer')
                  Autocomplete<Customer>(
                    displayStringForOption: (c) =>
                        '${c.name} · ${c.vatCondition}',
                    optionsBuilder: (value) {
                      final q = value.text.toLowerCase();
                      return customers.where((c) =>
                          c.name.toLowerCase().contains(q) ||
                          c.documentNumber.contains(q));
                    },
                    onSelected: (c) => setState(() => _customer = c),
                    fieldViewBuilder: (context, controller, focus, submit) =>
                        TextField(
                            controller: controller,
                            focusNode: focus,
                            decoration: const InputDecoration(
                                labelText:
                                    'Buscar cliente por nombre o documento')),
                  ),
                if (_mode == 'customer' && _customer != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                          '${_customer!.documentType} ${_customer!.documentNumber} · ${_customer!.vatCondition}')),
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : _skip,
            child: Text(widget.printTicketOnSkip
                ? 'No facturar · imprimir ticket'
                : 'Cancelar')),
        FilledButton(
            onPressed: _busy ? null : _issue,
            child: Text(_busy ? 'Pidiendo CAE…' : 'Facturar')),
      ],
    );
  }
}
