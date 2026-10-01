import 'package:bar_icecream_shop/models/price_list.dart';
import 'package:bar_icecream_shop/providers/price_list_provider.dart';
import 'package:bar_icecream_shop/providers/product_provider.dart';
import 'package:bar_icecream_shop/screens/price_lists/price_rules_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class FakeRules extends PriceListProvider {
  Map<String, dynamic>? saved;
  int? savedId;
  DateTime? quotedAt;
  @override
  Future<void> saveRule(int listId, Map<String, dynamic> rule,
      {int? id}) async {
    saved = rule;
    savedId = id;
  }

  @override
  Future<PagedProductPrices> getPrices(int listId,
          {int? idRubro,
          int? idSubRubro,
          String? texto,
          int page = 1,
          int pageSize = 30}) async =>
      const PagedProductPrices(items: [
        ProductPrice(
            idProducto: 1,
            codigo: 1,
            nombre: 'Café',
            rubro: ReferenciaSimple(id: 1, nombre: 'Bebidas'),
            precio: 1000)
      ], page: 1, totalPages: 1, totalItems: 1);
  @override
  Future<Map<int, Map<String, dynamic>>> quotePrices(List<int> productIds,
      {int? listId, DateTime? instant}) async {
    quotedAt = instant;
    return {
      1: {
        'idProducto': 1,
        'listaNombre': 'Salón',
        'precioBase': 1000,
        'precioFinal': 800,
        'reglaNombre': 'Happy hour'
      }
    };
  }
}

void main() {
  Map<String, dynamic> existing() => {
        'id': 7,
        'nombre': 'Happy hour',
        'activa': true,
        'prioridad': 5,
        'fechaDesde': '2026-10-02',
        'fechaHasta': '2026-10-30',
        'diasSemana': 16,
        'minutoDesde': 1320,
        'minutoHasta': 120,
        'operacion': 'DisminuirPorcentaje',
        'valor': 20,
        'redondeo': 100,
        'modoRedondeo': 'Arriba',
        'version': 3
      };
  Future<void> start(
      WidgetTester tester, FakeRules provider, Widget screen) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MultiProvider(providers: [
      ChangeNotifierProvider<PriceListProvider>.value(value: provider),
      ChangeNotifierProvider(create: (_) => ProductProvider()),
    ], child: MaterialApp(home: screen)));
    await tester.pumpAndSettle();
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.ensureVisible(find.text('Guardar regla'));
    await tester.tap(find.text('Guardar regla'));
    await tester.pumpAndSettle();
  }

  testWidgets('editing preserves dates, weekdays, overnight time and version',
      (tester) async {
    final provider = FakeRules();
    await start(tester, provider, PriceRuleEditor(listId: 2, rule: existing()));
    await submit(tester);
    expect(provider.savedId, 7);
    expect(provider.saved!['fechaDesde'], '2026-10-02');
    expect(provider.saved!['fechaHasta'], '2026-10-30');
    expect(provider.saved!['diasSemana'], 16);
    expect(provider.saved!['minutoDesde'], 1320);
    expect(provider.saved!['minutoHasta'], 120);
    expect(provider.saved!['version'], 3);
    expect(provider.saved!['valor'], 20);
  });
  testWidgets('no weekdays selected prevents saving', (tester) async {
    final provider = FakeRules();
    await start(tester, provider, PriceRuleEditor(listId: 2, rule: existing()));
    await tester.tap(find.widgetWithText(FilterChip, 'Vie'));
    await tester.pump();
    await submit(tester);
    expect(provider.saved, isNull);
    expect(find.text('Revisá el alcance, las fechas, los días y los horarios.'),
        findsOneWidget);
  });
  testWidgets('discount over 100 percent prevents saving', (tester) async {
    final provider = FakeRules();
    final rule = existing()..['valor'] = 101;
    await start(tester, provider, PriceRuleEditor(listId: 2, rule: rule));
    await submit(tester);
    expect(provider.saved, isNull);
    expect(find.text('Ingresá un valor válido (porcentaje: 0 a 100)'),
        findsOneWidget);
  });
  testWidgets(
      'simulation sends an explicit UTC instant and explains final price',
      (tester) async {
    final provider = FakeRules();
    await start(tester, provider, const PriceSimulationScreen(listId: 2));
    await tester.tap(find.text('Elegir producto'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('1 · Café'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Consultar'));
    await tester.pumpAndSettle();
    expect(provider.quotedAt!.isUtc, isTrue);
    expect(find.text('Regla aplicada: Happy hour'), findsOneWidget);
    expect(find.text('Precio final: \$800'), findsOneWidget);
  });
}
