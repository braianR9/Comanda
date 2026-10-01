import 'package:bar_icecream_shop/models/price_list.dart';
import 'package:bar_icecream_shop/providers/price_list_provider.dart';
import 'package:bar_icecream_shop/providers/product_provider.dart';
import 'package:bar_icecream_shop/screens/price_lists/price_grid_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class FakePrices extends PriceListProvider {
  List<Map<String, dynamic>>? saved;
  bool reject = false;
  @override
  List<PriceList> get activeLists => [
        for (var id = 1; id <= 2; id++)
          PriceList(
              id: id,
              nombre: id == 1 ? 'Salón' : 'Delivery',
              esPredeterminada: id == 1,
              activa: true,
              fechaCreacion: DateTime(2026),
              fechaModificacion: DateTime(2026))
      ];
  @override
  Future<PagedProductPrices> getPrices(int listId,
          {int? idRubro,
          int? idSubRubro,
          String? texto,
          int page = 1,
          int pageSize = 30}) async =>
      PagedProductPrices(items: [
        ProductPrice(
            idProducto: page,
            codigo: page,
            nombre: 'Producto $page',
            rubro: const ReferenciaSimple(id: 1, nombre: 'Bebidas'),
            precio: listId * 100.0)
      ], page: page, totalPages: 2, totalItems: 2);
  @override
  Future<void> saveGrid(List<Map<String, dynamic>> changes) async {
    if (reject) throw Exception('Los precios cambiaron. Recargá.');
    saved = changes;
  }
}

void main() {
  Future<void> start(WidgetTester tester, FakePrices prices) async {
    await tester.binding.setSurfaceSize(const Size(1200, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<PriceListProvider>.value(value: prices),
      ChangeNotifierProvider(create: (_) => ProductProvider()),
    ], child: const MaterialApp(home: PriceGridScreen())));
    await tester.pumpAndSettle();
  }

  Finder cell(int list, int product) => find.byKey(ValueKey((list, product)));
  Future<void> save(WidgetTester tester) async {
    await tester.pump();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Guardar'));
    await tester.pumpAndSettle();
  }

  testWidgets('edits survive paging and save together', (tester) async {
    final prices = FakePrices();
    await start(tester, prices);
    await tester.enterText(cell(1, 1), '123,45');
    await tester.tap(find.byIcon(Icons.chevron_right));
    await tester.pumpAndSettle();
    await tester.enterText(cell(2, 2), '250');
    await tester.tap(find.byIcon(Icons.chevron_left));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(cell(1, 1)).controller!.text, '123,45');
    expect(find.text('2 cambios pendientes'), findsOneWidget);
    await save(tester);
    expect(prices.saved, [
      {
        'idListaPrecio': 1,
        'idProducto': 1,
        'precioAnterior': 100.0,
        'precioNuevo': 123.45
      },
      {
        'idListaPrecio': 2,
        'idProducto': 2,
        'precioAnterior': 200.0,
        'precioNuevo': 250.0
      },
    ]);
    expect(find.text('0 cambios pendientes'), findsOneWidget);
  });
  testWidgets('invalid prices cannot be submitted', (tester) async {
    final prices = FakePrices();
    await start(tester, prices);
    await tester.enterText(cell(1, 1), '-10');
    await tester.pump();
    await tester.tap(find.text('Guardar cambios'));
    await tester.pumpAndSettle();
    expect(find.text('Precio inválido'), findsOneWidget);
    expect(prices.saved, isNull);
  });
  testWidgets('conflict preserves edits', (tester) async {
    final prices = FakePrices()..reject = true;
    await start(tester, prices);
    await tester.enterText(cell(1, 1), '125');
    await save(tester);
    expect(find.text('Los precios cambiaron. Recargá.'), findsOneWidget);
    expect(find.text('1 cambios pendientes'), findsOneWidget);
    expect(tester.widget<TextField>(cell(1, 1)).controller!.text, '125');
  });
  testWidgets('blank removes price and zero is preserved', (tester) async {
    final prices = FakePrices();
    await start(tester, prices);
    await tester.enterText(cell(1, 1), '');
    await tester.enterText(cell(2, 1), '0');
    await save(tester);
    expect(prices.saved![0]['precioNuevo'], isNull);
    expect(prices.saved![1]['precioNuevo'], 0);
  });
}
