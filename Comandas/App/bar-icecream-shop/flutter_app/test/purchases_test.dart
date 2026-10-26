import 'package:bar_icecream_shop/models/user_session.dart';
import 'package:bar_icecream_shop/providers/auth_provider.dart';
import 'package:bar_icecream_shop/screens/purchases/purchase_api.dart';
import 'package:bar_icecream_shop/screens/purchases/purchases_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

class PurchaseAuth extends AuthProvider {
  final String role;
  PurchaseAuth([this.role = 'ADMIN']);
  @override
  UserSession get session => UserSession.fromJson({
        'id': 1,
        'token': 'test',
        'nombre': 'Ana',
        'apellido': 'Test',
        'email': 'a@test',
        'idRol': 1,
        'idEmpresa': 1,
        'idSucursal': 1,
        'rol': {'id': 1, 'nombre': role},
        'empresa': {
          'id': 1,
          'nombre': 'Local',
          'cuit': null,
          'email': null,
          'telefono': null,
          'activa': true
        },
        'sucursal': {
          'id': 1,
          'idEmpresa': 1,
          'nombre': 'Centro',
          'direccion': '',
          'telefono': '',
          'activa': true
        }
      });
}

class PurchaseFake extends PurchaseApi {
  PurchaseFake() : super('test');
  bool fail = false;
  int controls = 0;
  Map<String, dynamic>? saved;
  final purchase = <String, dynamic>{
    'id': 5,
    'supplierId': 1,
    'supplierName': 'Proveedor',
    'version': 1,
    'requestKey': 'stable-key',
    'status': 'Borrador',
    'documentType': 'Remito',
    'letter': '',
    'pointOfSale': 0,
    'number': '7',
    'documentDate': '2026-10-14',
    'notes': '',
    'createdByName': 'Luis',
    'createdAt': '2026-10-14T12:00:00Z',
    'items': [
      {'productId': 1, 'productName': 'Harina', 'quantity': 2, 'unitCost': 100}
    ]
  };
  @override
  Future<dynamic> call(String path,
      {String method = 'GET', Map<String, dynamic>? body}) async {
    if (path == 'suppliers')
      return [
        {'id': 1, 'name': 'Proveedor', 'active': true}
      ];
    if (path == 'suppliers/1')
      return {
        'products': [
          {'productId': 1, 'name': 'Harina', 'activo': true, 'code': ''}
        ]
      };
    if (path == 'purchases/5/control') {
      controls++;
      if (fail) throw Exception('Stock no configurado');
      purchase['status'] = 'Controlado';
      purchase['controlledByName'] = 'Ana';
      purchase['controlledAt'] = '2026-10-14T13:00:00Z';
    }
    if (path == 'purchases/5' && method == 'PUT') {
      saved = body;
      purchase.addAll(body!);
      purchase['version'] = 2;
      purchase['items'] = [
        for (final r in body['items']) {...r, 'productName': 'Harina'}
      ];
    }
    return {'purchase': purchase, 'history': []};
  }
}

void main() {
  Future<void> start(WidgetTester tester, PurchaseFake api,
      {String role = 'ADMIN'}) async {
    await tester.binding.setSurfaceSize(const Size(1100, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider<AuthProvider>.value(
        value: PurchaseAuth(role),
        child: MaterialApp(home: PurchaseEditor(api: api, id: 5))));
    await tester.pumpAndSettle();
  }

  Future<void> click(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label));
    await tester.tap(find.text(label));
    await tester.pumpAndSettle();
  }

  testWidgets('control confirms branch and makes purchase read-only',
      (tester) async {
    final api = PurchaseFake();
    await start(tester, api);
    await click(tester, 'Controlar e ingresar al stock');
    expect(find.textContaining('Centro'), findsOneWidget);
    await click(tester, 'Confirmar ingreso');
    expect(api.controls, 1);
    expect(find.text('Compra #5 · Controlado'), findsOneWidget);
    expect(find.text('Guardar borrador'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'editing requires saving before control and preserves request key',
      (tester) async {
    final api = PurchaseFake();
    await start(tester, api);
    final qty = find.widgetWithText(TextFormField, 'Cantidad');
    await tester.ensureVisible(qty);
    await tester.enterText(qty, '3,5');
    await tester.pumpAndSettle();
    final control =
        find.widgetWithText(FilledButton, 'Controlar e ingresar al stock');
    await tester.ensureVisible(control);
    expect(tester.widget<FilledButton>(control).onPressed, isNull);
    await click(tester, 'Guardar borrador');
    expect(api.saved!['requestKey'], 'stable-key');
    expect(api.saved!['items'][0]['quantity'], 3.5);
    expect(api.controls, 0);
    await tester.ensureVisible(control);
    expect(tester.widget<FilledButton>(control).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
  testWidgets('failed control exits loading and keeps draft', (tester) async {
    final api = PurchaseFake()..fail = true;
    await start(tester, api);
    await click(tester, 'Controlar e ingresar al stock');
    await click(tester, 'Confirmar ingreso');
    expect(find.textContaining('Stock no configurado'), findsOneWidget);
    expect(find.text('Compra #5 · Borrador'), findsOneWidget);
    expect(find.text('Procesando…'), findsNothing);
    expect(tester.takeException(), isNull);
  });
  testWidgets('employee can save drafts but cannot control or cancel',
      (tester) async {
    await start(tester, PurchaseFake(), role: 'EMPLEADO');
    await tester.ensureVisible(find.text('Guardar borrador'));
    expect(find.text('Controlar e ingresar al stock'), findsNothing);
    expect(find.text('Anular borrador'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
