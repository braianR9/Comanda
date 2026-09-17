import 'dart:async';

import 'package:bar_icecream_shop/models/payment_amounts.dart';
import 'package:bar_icecream_shop/models/restaurant_table.dart';
import 'package:bar_icecream_shop/models/sector.dart';
import 'package:bar_icecream_shop/models/user_session.dart';
import 'package:bar_icecream_shop/providers/auth_provider.dart';
import 'package:bar_icecream_shop/providers/product_provider.dart';
import 'package:bar_icecream_shop/providers/sales_provider.dart';
import 'package:bar_icecream_shop/providers/sector_provider.dart';
import 'package:bar_icecream_shop/screens/sales/sales_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

SaleSnapshot snapshot(
        {int version = 1,
        double paid = 0,
        String status = 'PedidoEnviado',
        double total = 90,
        double adjustment = 0,
        bool hasPayment = false,
        List<int> joinedTableIds = const [],
        int quantity = 1}) =>
    SaleSnapshot.fromJson({
      'id': 1,
      'number': 1,
      'tableId': 1,
      'joinedTableIds': joinedTableIds,
      'version': version,
      'status': status,
      'total': total,
      'paymentAdjustment': adjustment,
      'discount': {'id': 1, 'name': 'Promo', 'type': 'Porcentaje', 'value': 10},
      'payments': [
        if (paid > 0 || hasPayment) {'amount': paid}
      ],
      'items': [
        {
          'id': 1,
          'productId': 1,
          'name': 'Café',
          'unitPrice': 100,
          'quantity': quantity
        }
      ],
    });

class FakeSales extends SalesProvider {
  SaleSnapshot current = snapshot();
  int paymentCalls = 0;
  int checkoutCalls = 0;
  int cancellationCalls = 0;
  bool failCheckout = true;
  bool losePaymentResponse = false;
  Completer<void>? paymentGate;
  List<SaleCatalogItem> methods = [const SaleCatalogItem(1, 'Efectivo')];
  List<SalePaymentInput> submitted = [];
  @override
  Future<List<SaleSnapshot>> getActiveSales() async => [current];
  @override
  Future<SaleSnapshot> getSale(int saleId) async => current;
  @override
  Future<List<SaleCatalogItem>> paymentTypes() async => methods;
  @override
  Future<List<SaleCatalogItem>> discounts() async =>
      [const SaleCatalogItem(1, 'Promo', type: 'Porcentaje', value: 10)];
  @override
  Future<SaleSnapshot> applyDiscount(int saleId, int version,
      {int? discountId,
      required String name,
      required String type,
      required double value}) async {
    expect(version, current.version);
    return current = snapshot(version: version + 1);
  }

  @override
  Future<SaleSnapshot> addPayments(
      int saleId, int version, List<SalePaymentInput> payments) async {
    expect(version, current.version);
    paymentCalls++;
    final amount = payments.fold<double>(0, (sum, p) => sum + p.amount);
    submitted = payments;
    final basis = payments.fold<double>(0, (sum, p) => sum + p.baseAmount);
    expect(basis, current.total - current.paidAmount);
    await paymentGate?.future;
    current = snapshot(
        version: version + 1,
        paid: current.paidAmount + amount,
        total: current.total + amount - basis,
        adjustment: current.paymentAdjustment + amount - basis,
        hasPayment: true);
    if (losePaymentResponse) {
      throw TimeoutException('Respuesta de pago perdida');
    }
    return current;
  }

  @override
  Future<SaleSnapshot> cancel(int saleId, int version) async {
    expect(version, current.version);
    cancellationCalls++;
    return current = snapshot(version: version + 1, status: 'Cancelada');
  }

  @override
  Future<SaleSnapshot> checkout(int saleId, int version) async {
    expect(version, current.version);
    checkoutCalls++;
    if (failCheckout) throw Exception('No se pudo cerrar');
    return current = snapshot(
        version: version + 1,
        paid: current.paidAmount,
        total: current.total,
        adjustment: current.paymentAdjustment,
        hasPayment: true,
        status: 'Finalizada');
  }
}

class FakeAuth extends AuthProvider {
  @override
  UserSession get session => UserSession.fromJson({
        'id': 1,
        'nombre': 'Test',
        'apellido': '',
        'email': '',
        'idRol': 1,
        'idEmpresa': 1,
        'idSucursal': 1,
        'empresa': {
          'id': 1,
          'nombre': '',
          'cuit': '',
          'email': '',
          'telefono': '',
          'activa': true
        },
        'sucursal': {
          'id': 1,
          'idEmpresa': 1,
          'nombre': '',
          'direccion': '',
          'telefono': '',
          'activa': true
        },
        'rol': {'id': 1, 'nombre': 'ADMIN'},
      });
}

class FakeSectors extends SectorProvider {
  @override
  List<Sector> get sectors => [const Sector(id: 1, name: 'Salón')];
  @override
  List<RestaurantTable> get tables => [
        const RestaurantTable(id: 1, number: 1, name: 'Mesa 1', sectorId: 1),
        const RestaurantTable(
            id: 2, number: 2, name: 'Mesa 2', sectorId: 1, positionX: .8)
      ];
  @override
  Future<void> load({required String token}) async {}
}

class FakeProducts extends ProductProvider {
  @override
  Future<void> load(int companyId,
      {String token = '', bool force = false}) async {}
}

Future<void> openSale(WidgetTester tester, FakeSales sales) async {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MultiProvider(providers: [
    ChangeNotifierProvider<AuthProvider>(create: (_) => FakeAuth()),
    ChangeNotifierProvider<SalesProvider>.value(value: sales),
    ChangeNotifierProvider<SectorProvider>(create: (_) => FakeSectors()),
    ChangeNotifierProvider<ProductProvider>(create: (_) => FakeProducts()),
  ], child: const MaterialApp(home: SalesScreen())));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Mesa 1'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => GoogleFonts.config.allowRuntimeFetching = false);

  test('payment amounts must be positive, finite and match the balance', () {
    expect(validPaymentAmounts([30, 60], 90), isTrue);
    expect(validPaymentAmounts([0.1, 0.2], 0.3), isTrue);
    for (final values in <List<double>>[
      [100],
      [89.99],
      [90.01],
      [100, -10],
      [90, 0],
      [double.nan],
      [double.infinity],
      [],
      [90, 0.001],
    ]) {
      expect(validPaymentAmounts(values, 90), isFalse, reason: '$values');
    }
  });

  test('restores persisted discount, balance and version', () {
    final sale = snapshot(version: 8, paid: 40);
    expect(sale.total, 90);
    expect(sale.paidAmount, 40);
    expect(sale.discount!.value, 10);
    expect(sale.version, 8);
  });

  testWidgets(
      'failed closing retains payment and retries without charging again',
      (tester) async {
    final sales = FakeSales();
    await openSale(tester, sales);
    await tester.tap(find.text('Cobrar cuenta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Confirmar cobro'));
    await tester.pumpAndSettle();
    expect(sales.paymentCalls, 1);
    expect(sales.checkoutCalls, 1);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.close_rounded))
            .onPressed,
        isNull);
    expect(
        tester
            .widget<OutlinedButton>(find.ancestor(
                of: find.text('Cambiar descuento'),
                matching: find
                    .byWidgetPredicate((widget) => widget is OutlinedButton)))
            .onPressed,
        isNull);
    sales.failCheckout = false;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completar cobro'));
    await tester.pumpAndSettle();
    expect(sales.paymentCalls, 1);
    expect(sales.checkoutCalls, 2);
    expect(find.textContaining('La mesa quedó cerrada.'), findsOneWidget);
  });

  testWidgets('processing a payment blocks order removal and repeated checkout',
      (tester) async {
    final sales = FakeSales()..paymentGate = Completer<void>();
    await openSale(tester, sales);
    await tester.tap(find.text('Cobrar cuenta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Confirmar cobro'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.byIcon(Icons.close_rounded), warnIfMissed: false);
    await tester.tap(find.text('Cobrar cuenta').first, warnIfMissed: false);
    await tester.pump();
    expect(sales.paymentCalls, 1);
    expect(find.text('Café'), findsOneWidget);
    sales.paymentGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('a restored partial payment only collects the remaining balance',
      (tester) async {
    final sales = FakeSales()
      ..current = snapshot(paid: 40)
      ..failCheckout = false;
    await openSale(tester, sales);
    await tester.tap(find.text('Completar cobro'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.widgetWithText(TextFormField, '50.0'), findsOneWidget);
    await tester.tap(find.text('Confirmar cobro'));
    await tester.pumpAndSettle();
    expect(sales.paymentCalls, 1);
    expect(sales.checkoutCalls, 1);
  });

  testWidgets('discount updates version and still permits checkout',
      (tester) async {
    final sales = FakeSales()..failCheckout = false;
    await openSale(tester, sales);
    await tester.tap(find.text('Cambiar descuento'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(find.text('Cobrar cuenta'), findsOneWidget);
    await tester.tap(find.text('Cobrar cuenta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Confirmar cobro'));
    await tester.pumpAndSettle();
    expect(sales.checkoutCalls, 1);
  });
  testWidgets('lost payment response is recovered without a second payment',
      (tester) async {
    final sales = FakeSales()
      ..losePaymentResponse = true
      ..failCheckout = false;
    await openSale(tester, sales);
    await tester.tap(find.text('Cobrar cuenta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Confirmar cobro'));
    await tester.pumpAndSettle();
    expect(sales.paymentCalls, 1);
    expect(sales.checkoutCalls, 0);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completar cobro'));
    await tester.pumpAndSettle();
    expect(sales.paymentCalls, 1);
    expect(sales.checkoutCalls, 1);
  });

  testWidgets('a concurrent change refreshes the account before taking payment',
      (tester) async {
    final sales = FakeSales();
    await openSale(tester, sales);
    sales.current = snapshot(version: 2, total: 80);
    await tester.tap(find.text('Cobrar cuenta'));
    await tester.pumpAndSettle();
    expect(sales.paymentCalls, 0);
    expect(find.text('Confirmar cobro'), findsNothing);
    expect(find.textContaining('La cuenta se actualizó.'), findsOneWidget);
    expect(find.text(r'$80.00'), findsOneWidget);
  });
  test('payment percentages round per assigned portion', () {
    expect(paymentAdjustment(60, 'Recargo', 20), 12);
    expect(paymentAdjustment(40, 'Descuento', 10), -4);
    expect(paymentAdjustment(0.05, 'Recargo', 10), 0.01);
    expect(paymentAdjustment(90, 'Descuento', 100), -90);
    expect(paymentAdjustment(90, 'SinAjuste', 0), 0);
  });

  for (final entry in [
    ('Recargo', 10.0, 99.0),
    ('Descuento', 10.0, 81.0),
    ('Descuento', 100.0, 0.0)
  ]) {
    testWidgets(
        '${entry.$1} ${entry.$2}% updates preview and submitted payment',
        (tester) async {
      final sales = FakeSales()
        ..methods = [
          SaleCatalogItem(7, 'Pago del maestro',
              type: entry.$1, value: entry.$2)
        ]
        ..failCheckout = false;
      await openSale(tester, sales);
      await tester.tap(find.text('Cobrar cuenta'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(
          find.text(
              'A cobrar con este medio: \$${entry.$3.toStringAsFixed(2)}'),
          findsOneWidget);
      await tester.tap(find.text('Confirmar cobro'));
      await tester.pumpAndSettle();
      expect(sales.submitted.single.cardId, 7);
      expect(sales.submitted.single.baseAmount, 90);
      expect(sales.submitted.single.amount, entry.$3);
      expect(sales.current.total, entry.$3);
      expect(sales.checkoutCalls, 1);
    });
  }

  testWidgets('mixed payment methods calculate each portion separately',
      (tester) async {
    final sales = FakeSales()
      ..methods = [
        const SaleCatalogItem(1, 'Efectivo', type: 'Descuento', value: 10),
        const SaleCatalogItem(2, 'Tarjeta', type: 'Recargo', value: 20)
      ]
      ..failCheckout = false;
    await openSale(tester, sales);
    await tester.tap(find.text('Cobrar cuenta'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.enterText(find.byType(TextFormField), '40');
    await tester.tap(find.text('Agregar otro medio de pago'));
    await tester.pump();
    await tester.enterText(find.byType(TextFormField).last, '50');
    await tester
        .tap(find.byType(DropdownButtonFormField<SaleCatalogItem>).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Tarjeta').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('A cobrar con este medio: \$36.00'), findsOneWidget);
    expect(find.text('A cobrar con este medio: \$60.00'), findsOneWidget);
    await tester.tap(find.text('Confirmar cobro'));
    await tester.pumpAndSettle();
    expect(sales.submitted.map((p) => p.amount), [36, 60]);
    expect(sales.current.total, 96);
  });

  testWidgets('zero amount payment still locks editing after closing fails',
      (tester) async {
    final sales = FakeSales()
      ..current = snapshot(total: 0, adjustment: -90, hasPayment: true);
    await openSale(tester, sales);
    expect(
        tester
            .widget<IconButton>(
                find.widgetWithIcon(IconButton, Icons.close_rounded))
            .onPressed,
        isNull);
    expect(find.text('Completar cobro'), findsOneWidget);
    await tester.tap(find.text('Completar cobro'));
    await tester.pumpAndSettle();
    expect(sales.paymentCalls, 0);
    expect(sales.checkoutCalls, 1);
  });
  testWidgets('restored joined tables remain gray and cannot open the account',
      (tester) async {
    final sales = FakeSales()..current = snapshot(joinedTableIds: [2]);
    await openSale(tester, sales);
    await tester.tap(find.byTooltip('Volver a las mesas'));
    await tester.pumpAndSettle();
    final secondary = find
        .ancestor(of: find.text('Mesa 2'), matching: find.byType(InkWell))
        .first;
    expect(tester.widget<InkWell>(secondary).onTap, isNull);
    final surface = find
        .ancestor(of: find.text('Mesa 2'), matching: find.byType(Material))
        .first;
    expect(tester.widget<Material>(surface).color, const Color(0xFFE5E7EB));
    await tester.tap(find.text('Mesa 2'));
    await tester.pumpAndSettle();
    expect(find.text('Comanda'), findsNothing);
    await tester.tap(find.text('Mesa 1'));
    await tester.pumpAndSettle();
    expect(find.text('Comanda'), findsOneWidget);
    await tester.tap(find.byTooltip('Acciones de mesa'));
    await tester.pumpAndSettle();
    final move = find.ancestor(
        of: find.text('Cambiar de mesa'),
        matching: find.byType(PopupMenuItem<String>));
    expect(tester.widget<PopupMenuItem<String>>(move).enabled, isFalse);
    expect(find.text('No disponible con mesas unidas'), findsOneWidget);
  });
  testWidgets(
      'last sent product becomes a pending annulment to send to kitchen',
      (tester) async {
    final sales = FakeSales();
    await openSale(tester, sales);
    await tester.tap(find.byTooltip('Anular producto'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Anular producto'), findsOneWidget);
    expect(sales.cancellationCalls, 0);
    await tester.tap(find.text('Volver'));
    await tester.pumpAndSettle();
    expect(find.text('Café'), findsOneWidget);
    await tester.tap(find.byTooltip('Anular una unidad'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.tap(find.text('Confirmar anulación'));
    await tester.pumpAndSettle();
    expect(sales.cancellationCalls, 0);
    expect(find.text('Enviar cambios'), findsOneWidget);
    expect(find.textContaining('Anulaciones pendientes: 1 × Café'),
        findsOneWidget);
  });

  testWidgets(
      'reducing a sent quantity confirms and displays a pending annulment',
      (tester) async {
    final sales = FakeSales()..current = snapshot(quantity: 2);
    await openSale(tester, sales);
    await tester.tap(find.byTooltip('Anular una unidad'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Anular producto'), findsOneWidget);
    await tester.tap(find.text('Confirmar anulación'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Anulaciones pendientes: 1 × Café'),
        findsOneWidget);
    expect(find.text('Enviar cambios'), findsOneWidget);
    expect(sales.cancellationCalls, 0);
    expect(sales.paymentCalls, 0);
  });
}
