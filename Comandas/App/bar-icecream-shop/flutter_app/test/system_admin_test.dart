import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:focobr/providers/system_admin_provider.dart';
import 'package:focobr/screens/system/system_admin_screen.dart';
import 'package:focobr/utils/client_diagnostics.dart';

void main() {
  late List<http.Request> requests;
  late bool expired;
  late MockClient client;
  setUp(() {
    requests = [];
    expired = false;
    client = MockClient((request) async {
      requests.add(request);
      if (expired) {
        return http.Response('{"codigo":401,"error":"La sesión venció."}', 401);
      }
      final path = request.url.path;
      dynamic data;
      if (path.endsWith('/login')) {
        data = {
          'token': 'private-owner-session',
          'email': 'owner@example.test'
        };
      } else if (path.endsWith('/roles')) {
        data = [
          {'id': 1, 'nombre': 'ADMIN'},
          {'id': 2, 'nombre': 'CAJA'},
          {'id': 3, 'nombre': 'EMPLEADO'}
        ];
      } else if (path.endsWith('/branches')) {
        data = [
          {'id': 2, 'nombre': 'Centro', 'activa': true}
        ];
      } else if (path.endsWith('/users') && request.method == 'GET') {
        data = {
          'items': [
            {
              'id': 3,
              'nombre': 'Ana',
              'apellido': 'Prueba',
              'email': 'ana@example.test',
              'idRol': 3,
              'rolNombre': 'EMPLEADO',
              'idSucursal': 2,
              'sucursalNombre': 'Centro',
              'activo': true
            }
          ],
          'total': 1
        };
      } else if (request.method == 'GET' && path.endsWith('/companies')) {
        data = {
          'items': [
            {
              'id': 1,
              'nombre': 'Negocio',
              'activa': true,
              'branches': 1,
              'users': 1
            }
          ],
          'total': 1
        };
      } else if (path.endsWith('/transactions') || path.endsWith('/events')) {
        data = {'items': [], 'total': 0, 'daily': [], 'amount': 0};
      } else {
        data = {'id': 4};
      }
      return http.Response(jsonEncode({'codigo': 200, 'data': data}), 200,
          headers: {'content-type': 'application/json'});
    });
  });

  test('Owner requests carry their own token and logout clears all global data',
      () async {
    final model = SystemAdminProvider(client: client);
    await model.login('owner@example.test', 'test-password');
    expect(model.authenticated, isTrue);
    expect(requests.first.headers.containsKey('Authorization'), isFalse);
    expect(
        requests.last.headers['Authorization'], 'Bearer private-owner-session');
    expect(ClientDiagnostics.ownerToken, 'private-owner-session');
    model.logout();
    expect(model.authenticated, isFalse);
    expect(model.rows, isEmpty);
    expect(model.roles, isEmpty);
    expect(ClientDiagnostics.ownerToken, isNull);
    expect(model.busy, isFalse);
    expect(model.companyId, isNull);
    expired = false;
    await model.login('owner@example.test', 'test-password');
    expect(model.authenticated, isTrue);
    expect(model.section, 0);
    expect(model.busy, isFalse);
    model.dispose();
  });

  test(
      'Transactions use the selected day boundaries and company/branch filters',
      () async {
    final model = SystemAdminProvider(client: client);
    await model.login('owner@example.test', 'test-password');
    model.from = DateTime(2026, 5, 20);
    model.to = DateTime(2026, 5, 22);
    await model.selectCompany({'id': 1, 'nombre': 'Negocio'}, openSection: 2);
    model.branchId = 2;
    model.transactionKind = 'payments';
    await model.load();
    final query = requests.last.url.queryParameters;
    expect(DateTime.parse(query['from']!), DateTime(2026, 5, 20).toUtc());
    expect(DateTime.parse(query['to']!), DateTime(2026, 5, 23).toUtc());
    expect(query['company'], '1');
    expect(query['branch'], '2');
    expect(query['kind'], 'payments');
    expired = true;
    await model.load();
    expect(model.authenticated, isFalse);
    expect(model.rows, isEmpty);
    expect(model.roles, isEmpty);
    expect(ClientDiagnostics.ownerToken, isNull);
    expect(model.busy, isFalse);
    expect(model.companyId, isNull);
    expired = false;
    await model.login('owner@example.test', 'test-password');
    expect(model.authenticated, isTrue);
    expect(model.section, 0);
    expect(model.busy, isFalse);
    model.dispose();
  });

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        home: SystemAdminScreen(
            createProvider: () => SystemAdminProvider(client: client))));
    expect(find.text('Acceso exclusivo del propietario del sistema.'),
        findsOneWidget);
    expect(find.text('Nueva empresa'), findsNothing);
    await tester.enterText(
        find.byType(TextFormField).at(0), 'owner@example.test');
    await tester.enterText(find.byType(TextFormField).at(1), 'test-password');
    await tester.tap(find.text('Ingresar a sistemas'));
    await tester.pumpAndSettle();
    expect(find.text('focobr · Sistemas'), findsOneWidget);
  }

  testWidgets('Owner can create a disabled company and close the editor safely',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Nueva empresa'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find
            .descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(TextFormField))
            .first,
        'Nueva empresa de prueba');
    await tester.tap(find.byType(Switch));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final saved = requests.singleWhere(
        (r) => r.method == 'POST' && r.url.path.endsWith('/companies'));
    final body = jsonDecode(saved.body) as Map<String, dynamic>;
    expect(body['nombre'], 'Nueva empresa de prueba');
    expect(body['activa'], isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'User editor preserves branch and role while disabling the account',
      (tester) async {
    await open(tester);
    await tester.tap(find.text('Usuarios').last);
    await tester.pumpAndSettle();
    expect(find.text('Ana Prueba'), findsOneWidget);
    await tester.tap(find.byTooltip('Modificar usuario'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(Switch));
    await tester.tap(find.byType(Switch));
    await tester.tap(find.text('Guardar'));
    await tester.pumpAndSettle();
    final saved = requests.singleWhere(
        (r) => r.method == 'PUT' && r.url.path.endsWith('/users/3'));
    final body = jsonDecode(saved.body) as Map<String, dynamic>;
    expect(body['activo'], isFalse);
    expect(body['idSucursal'], 2);
    expect(body['idRol'], 3);
    expect(body['password'], '');
    expect(tester.takeException(), isNull);
  });
}
