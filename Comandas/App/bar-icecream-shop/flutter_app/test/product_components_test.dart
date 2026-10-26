import 'package:bar_icecream_shop/models/product.dart';
import 'package:bar_icecream_shop/models/product_component.dart';
import 'package:bar_icecream_shop/providers/product_provider.dart';
import 'package:bar_icecream_shop/screens/products/product_components_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class ComponentProducts extends ProductProvider {
  final queries = <String>[];
  @override
  Future<List<ProductComponent>> searchSimpleComponents(String text) async {
    queries.add(text);
    return [
      const ProductComponent(productId: 1, name: 'Pan', quantity: 1),
      const ProductComponent(productId: 2, name: 'Queso', quantity: 1)
    ];
  }
}

void main() {
  test('composition survives serialization and edits to other product fields',
      () {
    final product = Product(
        id: '10',
        name: 'Combo',
        category: '',
        price: 100,
        components: [
          const ProductComponent(productId: 1, name: 'Pan', quantity: 2)
        ]);
    final restored =
        Product.fromJson(product.copyWith(name: 'Combo nuevo').toJson());
    expect(restored.components!.single.quantity, 2);
    expect(restored.components!.single.productId, 1);
  });
  testWidgets('add, change quantity, prevent duplicate and remove components',
      (tester) async {
    final provider = ComponentProducts();
    var components = <ProductComponent>[];
    await tester.pumpWidget(ChangeNotifierProvider<ProductProvider>.value(
        value: provider,
        child: MaterialApp(
            home: Scaffold(
                body: StatefulBuilder(
                    builder: (context, setState) => Form(
                          child: ProductComponentsEditor(
                              productId: 10,
                              components: components,
                              onChanged: (values) =>
                                  setState(() => components = values)),
                        ))))));
    await tester.tap(find.text('Agregar producto simple'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Pan'));
    await tester.pumpAndSettle();
    expect(components.single.productId, 1);
    await tester.enterText(find.byType(TextFormField), '2,5');
    expect(components.single.quantity, 2.5);
    await tester.tap(find.text('Agregar producto simple'));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(AlertDialog), matching: find.text('Pan')),
        findsNothing);
    await tester.enterText(find.byType(TextField).last, 'Queso');
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(provider.queries.last, 'Queso');
    await tester.tap(find.widgetWithText(ListTile, 'Queso'));
    await tester.pumpAndSettle();
    expect(components.length, 2);
    await tester.tap(find.byTooltip('Quitar componente').first);
    await tester.pump();
    expect(components.single.name, 'Queso');
  });
}
