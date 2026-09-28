// Prueba de humo de la app completa: arranca, muestra los términos y, según
// la respuesta del ciudadano, el formulario o el aviso. No llama al servicio.
//
//     flutter test test/widget_test.dart

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_formulario_rifa/componentes/tarjetaFormulario.dart';
import 'package:flutter_formulario_rifa/main.dart';

Future<void> arrancarApp(WidgetTester tester) async {
  // Pantalla alta para que el formulario completo quepa sin desbordarse
  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(const RifaPredialApp());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('al arrancar pide aceptar los términos', (tester) async {
    await arrancarApp(tester);
    expect(find.text('Aviso de Privacidad y Términos'), findsOneWidget);
    expect(find.byType(TarjetaFormulario), findsNothing);
  });

  testWidgets('al aceptar los términos aparece el formulario', (tester) async {
    await arrancarApp(tester);
    await tester.tap(find.text('Aceptar'));
    await tester.pumpAndSettle();

    expect(find.text('Aviso de Privacidad y Términos'), findsNothing);
    expect(find.byType(TarjetaFormulario), findsOneWidget);
  });

  testWidgets('sin aceptar los términos no hay formulario', (tester) async {
    await arrancarApp(tester);
    await tester.tap(find.text('No Acepto'));
    await tester.pumpAndSettle();

    expect(find.byType(TarjetaFormulario), findsNothing);
    expect(find.text('Aviso de Privacidad Requerido'), findsOneWidget);
    expect(find.text('Revisar Términos'), findsOneWidget);
  });
}
