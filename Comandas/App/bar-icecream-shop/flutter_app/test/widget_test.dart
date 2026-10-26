import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bar_icecream_shop/screens/auth/login_screen.dart';
import 'package:bar_icecream_shop/providers/auth_provider.dart';

void main() {
  testWidgets('Login screen renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    // La pantalla de login debe mostrar los campos y el botón
    expect(find.text('Iniciá sesión'), findsOneWidget);
    expect(find.text('Ingresar al panel'), findsOneWidget);
  });
}
