import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:discord_epn/ui/auth/login_screen.dart';

void main() {
  testWidgets('LoginScreen renderiza campos de Discord y formulario correctamente', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(),
      ),
    );

    // Verificar textos de Discord
    expect(find.text('¡Te damos la bienvenida de nuevo!'), findsOneWidget);
    expect(find.text('CORREO ELECTRÓNICO *'), findsOneWidget);
    expect(find.text('CONTRASEÑA *'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsOneWidget);
    expect(find.text('Registrarse'), findsOneWidget);

    // Verificar campos de texto
    expect(find.byType(TextFormField), findsNWidgets(2));
  });
}
