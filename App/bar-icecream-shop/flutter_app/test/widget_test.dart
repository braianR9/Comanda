import 'package:flutter_test/flutter_test.dart';
import 'package:bar_icecream_shop/main.dart';

void main() {
  testWidgets('Login screen renders correctly', (WidgetTester tester) async {
    await tester.pumpWidget(const BarApp());
    await tester.pumpAndSettle();

    // La pantalla de login debe mostrar los campos y el botón
    expect(find.text('Iniciá sesión'), findsOneWidget);
    expect(find.text('Ingresar al panel'), findsOneWidget);
  });
}
