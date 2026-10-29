import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:focobr/screens/invoices/invoices_screen.dart';
import 'package:focobr/screens/invoices/void_sale_dialog.dart';
import 'package:focobr/screens/purchases/purchase_api.dart';

class _Api extends PurchaseApi {
  _Api() : super('test');
  bool voided = false, canVoid = true, fail = false;
  Completer<void>? pending;
  Map<String, dynamic>? submitted;
  @override
  Future<dynamic> call(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    if (method == 'POST') {
      expect(path, 'sales/42/void');
      submitted = body;
      await pending?.future;
      if (fail) throw Exception('Abrí la caja para registrar la devolución.');
      voided = true;
      return {'saleId': 42};
    }
    final items = path.startsWith('facturacion/pendientes') && !voided
        ? [
            {
              'saleId': 42,
              'saleNumber': 8,
              'closedAt': '2026-10-29T12:00:00Z',
              'total': 100,
              'table': 'Mesa 1',
              'cashier': 'Caja',
              'version': 3,
              'canVoid': canVoid
            }
          ]
        : path.startsWith('sales/voids') && voided
            ? [
                {
                  'saleId': 42,
                  'saleNumber': 8,
                  'closedAt': '2026-10-29T12:00:00Z',
                  'at': '2026-10-29T13:00:00Z',
                  'reason': submitted!['reason'],
                  'refunded': 100,
                  'userName': 'Responsable Caja'
                }
              ]
            : [];
    return {
      'items': items,
      'page': 1,
      'totalPages': 1,
      'totalItems': items.length
    };
  }
}

void main() {
  testWidgets('Reason is required and submitting cannot duplicate the request',
      (tester) async {
    final api = _Api()..pending = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => showDialog<bool>(
                          context: context,
                          builder: (_) => VoidSaleDialog(
                              api: api,
                              saleId: 42,
                              saleNumber: 8,
                              version: 3,
                              total: 100)),
                      child: const Text('Abrir'),
                    )))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anular venta'));
    await tester.pump();
    expect(find.textContaining('mínimo 3 caracteres'), findsOneWidget);
    expect(api.submitted, isNull);
    await tester.enterText(find.byType(TextField), '  Cobro duplicado  ');
    await tester.tap(find.text('Anular venta'));
    await tester.pump();
    expect(api.submitted, {'reason': 'Cobro duplicado', 'version': 3});
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Anulando…'))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancelar'))
            .onPressed,
        isNull);
    api.pending!.complete();
    await tester.pumpAndSettle();
    expect(find.byType(VoidSaleDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'A voided sale leaves pending sales and appears with reason and actor in history',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _Api();
    await tester
        .pumpWidget(MaterialApp(home: InvoicesScreen(api: api, initialTab: 1)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Anular venta'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anular venta'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Error de carga');
    await tester.tap(find.widgetWithText(FilledButton, 'Anular venta'));
    await tester.pumpAndSettle();
    expect(api.voided, isTrue);
    expect(find.text('Todas las ventas cobradas están facturadas.'),
        findsOneWidget);
    await tester.tap(find.text('Ventas anuladas'));
    await tester.pumpAndSettle();
    expect(find.text('Error de carga'), findsOneWidget);
    expect(find.text('Responsable Caja'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'Server errors keep the reason and allow correcting or cancelling',
      (tester) async {
    final api = _Api()..fail = true;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: VoidSaleDialog(
                api: api, saleId: 42, saleNumber: 8, version: 3, total: 100))));
    await tester.enterText(find.byType(TextField), 'Error de carga');
    await tester.tap(find.text('Anular venta'));
    await tester.pumpAndSettle();
    expect(find.text('Abrí la caja para registrar la devolución.'),
        findsOneWidget);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Error de carga');
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNotNull);
    expect(api.voided, isFalse);
  });
}
