// Revisión adversarial del formulario (29 sep 2026).
//
//     flutter test test/revision_adversarial_test.dart
//
// Tercera ronda: se intentó romper lo que ya se había corregido en las
// revisiones anteriores (revision_test.dart y revision_critica_test.dart).
// Los defectos de esta ronda están en el servicio
// (servicio_rifa/tests/test_revision_adversarial.py). Aquí quedan los
// ataques al formulario que NO lo rompieron, como protección para que no se
// vuelvan posibles.
//
// Convención (igual que en las otras revisiones):
//   * group 'FALLA ...'    -> defecto confirmado.
//   * group 'SUPUESTO ...' -> el código asume algo que no está garantizado.
//   * group 'GUARDIA ...'  -> ataque que hoy no funciona; debe seguir así.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_formulario_rifa/componentes/boleto.dart';
import 'package:flutter_formulario_rifa/componentes/confirmacion.dart';
import 'package:flutter_formulario_rifa/pantallas/formulario_screen.dart';
import 'package:flutter_formulario_rifa/servicios/servicio_rifa.dart';

/// Monta la pantalla con un servicio simulado, acepta los términos, llena el
/// formulario y lo envía hasta que aparece el modal de confirmación.
/// Devuelve las rutas que la app llamó (se siguen llenando después).
Future<List<String>> llegarAlModal(WidgetTester tester) async {
  final llamadas = <String>[];
  final servicio = ServicioRifa(
    base: Uri.parse('https://rifa.ejemplo.gob.mx/'),
    cliente: MockClient((req) async {
      final cuerpo = jsonDecode(req.body) as Map<String, dynamic>;
      llamadas.add(req.url.path);
      final respuesta = req.url.path == '/api/validar'
          ? {'ok': true, 'direccion': 'CALLE OFICIAL 120'}
          : {
              'ok': true,
              'mensaje': 'Registro completado exitosamente.',
              'boleto': {'txca': cuerpo['txca'], 'nombre': 'ANA GARCIA'},
            };
      return http.Response.bytes(utf8.encode(jsonEncode(respuesta)), 200,
          headers: {'content-type': 'application/json'});
    }),
  );

  tester.view.physicalSize = const Size(1000, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(home: FormularioScreen(servicio: servicio)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Aceptar')); // términos y condiciones
  await tester.pumpAndSettle();

  final campos = find.byType(TextFormField);
  for (final (i, texto) in [
    (0, 'ANA'),
    (1, 'GARCIA'),
    (3, '6181234567'),
    (4, '337308'),
    (5, '03092026'),
  ]) {
    await tester.enterText(campos.at(i), texto);
  }
  await tester.pump();
  await tester.tap(find.text('Aceptar')); // enviar -> /api/validar
  await tester.pumpAndSettle();
  expect(find.byType(ConfirmacionDialog), findsOneWidget,
      reason: 'No apareció el modal de confirmación');
  return llamadas;
}

void main() {
  group('GUARDIA: confirmar dos veces no cierra la pantalla del formulario', () {
    // ConfirmacionDialog llama onConfirmar con Enter (Focus con autofocus) y
    // con el botón, y onConfirmar hace Navigator.pop() ANTES de la guarda de
    // _registrarBoleto (FormStatus.guardando). Si un segundo Enter o toque
    // llegara al modal mientras se cierra, ese segundo pop() sacaría la
    // PANTALLA del formulario: pantalla en blanco sin boleto aunque el
    // registro sí se hizo. Hoy Flutter deja de entregar eventos al modal en
    // cuanto empieza a cerrarse, incluso dentro del mismo frame. Si alguien
    // cambia el modal (otra animación, otro manejo de teclas), esto lo avisa.

    testWidgets('dos Enter seguidos registran una vez y muestran el boleto',
        (tester) async {
      final llamadas = await llegarAlModal(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      // Sin pump(): ambos eventos llegan dentro del mismo frame.
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(llamadas.where((r) => r == '/api/registrar').length, 1);
      expect(find.byType(FormularioScreen), findsOneWidget,
          reason: 'El segundo Enter sacó la pantalla del formulario');
      expect(find.byType(Boleto), findsOneWidget,
          reason: 'El ciudadano se registró pero no ve su boleto');
    });

    testWidgets('dos toques rápidos en "Aceptar" registran una vez y muestran '
        'el boleto', (tester) async {
      final llamadas = await llegarAlModal(tester);

      final confirmar = find.descendant(
          of: find.byType(ConfirmacionDialog), matching: find.text('Aceptar'));
      final punto = tester.getCenter(confirmar);
      await tester.tapAt(punto);
      // Sin pump(): ambos eventos llegan dentro del mismo frame.
      await tester.tapAt(punto);
      await tester.pumpAndSettle();

      expect(llamadas.where((r) => r == '/api/registrar').length, 1);
      expect(find.byType(FormularioScreen), findsOneWidget,
          reason: 'El segundo toque sacó la pantalla del formulario');
      expect(find.byType(Boleto), findsOneWidget,
          reason: 'El ciudadano se registró pero no ve su boleto');
    });
  });
}
