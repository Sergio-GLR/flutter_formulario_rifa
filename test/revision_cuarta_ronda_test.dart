// Cuarta revisión: intentar romper el formulario (1 oct 2026).
//
//     flutter test test/revision_cuarta_ronda_test.dart
//
// NO se corrigió nada: los grupos FALLA fallan con el código actual y deben
// pasar cuando se corrija cada defecto. Los defectos del servicio de esta
// ronda están en servicio_rifa/tests/test_revision_cuarta_ronda.py.
//
// Convención (igual que en las otras revisiones):
//   * group 'FALLA ...'    -> defecto confirmado.
//   * group 'SUPUESTO ...' -> el código asume algo que no está garantizado.
//   * group 'GUARDIA ...'  -> ataque que hoy no funciona; debe seguir así.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_formulario_rifa/componentes/confirmacion.dart';
import 'package:flutter_formulario_rifa/pantallas/formulario_screen.dart';
import 'package:flutter_formulario_rifa/servicios/servicio_rifa.dart';
import 'package:flutter_formulario_rifa/validadores/validadores.dart';

/// Lo que acepta el servicio en nombres y apellidos (RE_NOMBRE en
/// servicio_rifa/app.py), después de juntar espacios como hace `_texto`.
final reNombreDelServicio = RegExp(r'^[A-ZÁÉÍÓÚÜÑ]+( [A-ZÁÉÍÓÚÜÑ]+)*$');

/// Monta la pantalla con un servicio simulado y acepta los términos.
/// Devuelve los cuerpos que la app envió, por ruta.
Future<Map<String, List<Map<String, dynamic>>>> montar(
    WidgetTester tester) async {
  final enviados = <String, List<Map<String, dynamic>>>{};
  final servicio = ServicioRifa(
    base: Uri.parse('https://rifa.ejemplo.gob.mx/'),
    cliente: MockClient((req) async {
      final cuerpo = jsonDecode(req.body) as Map<String, dynamic>;
      enviados.putIfAbsent(req.url.path, () => []).add(cuerpo);
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

  await tester.pumpWidget(
      MaterialApp(home: FormularioScreen(servicio: servicio)));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Aceptar')); // términos y condiciones
  await tester.pumpAndSettle();
  return enviados;
}

Future<void> llenar(
  WidgetTester tester, {
  String nombre = 'ANA',
  String paterno = 'GARCIA',
  String telefono = '6181234567',
  String transaccion = '337308',
  String fecha = '03092026',
}) async {
  final campos = find.byType(TextFormField);
  for (final (i, texto) in [
    (0, nombre),
    (1, paterno),
    (3, telefono),
    (4, transaccion),
    (5, fecha),
  ]) {
    await tester.enterText(campos.at(i), texto);
  }
  await tester.pump();
}

void main() {
  group('FALLA: el prefijo del folio muestra un año y se envía otro', () {
    // El campo de transacción pinta el prefijo con DateTime.now().year
    // (tarjetaFormulario.dart), pero desde la revisión crítica la txca se
    // arma con el año de la FECHA DE PAGO (formulario_screen.dart). Quien
    // pagó en diciembre de 2025 y se registra en 2026 escribe su folio junto
    // a un "2026-" que no es el de su recibo; el modal de confirmación le
    // muestra "2025-...". Lo que se ve y lo que se envía deben coincidir.
    //
    // Corregido (1 oct 2026): el prefijo usa Validadores.anioDelFolio (año de
    // la fecha de pago; el actual mientras no haya fecha válida) y se
    // reconstruye al escribir la fecha.
    testWidgets('con fecha de pago de 2025 el prefijo visible es "2025-"',
        (tester) async {
      final enviados = await montar(tester);
      await llenar(tester, fecha: '15122025');
      await tester.tap(find.byType(TextFormField).at(4)); // enfocar el folio
      await tester.pump();

      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      expect(find.byType(ConfirmacionDialog), findsOneWidget);
      final txcaEnviada = enviados['/api/validar']!.single['txca'] as String;
      expect(txcaEnviada, '2025-337308');

      // Cerrar el modal y mirar el campo que el ciudadano escribió
      await tester.tap(find.text('Cancelar').last);
      await tester.pumpAndSettle();
      expect(find.text('2025-'), findsOneWidget,
          reason: 'El campo muestra "${DateTime.now().year}-" pero se envió '
              '"$txcaEnviada"');
    });
  });

  group('GUARDIA: el prefijo sigue a la fecha mientras se escribe', () {
    testWidgets('sin fecha muestra el año actual; con fecha, el del pago',
        (tester) async {
      await montar(tester);
      final folio = find.byType(TextFormField).at(4);
      final fecha = find.byType(TextFormField).at(5);
      await tester.enterText(folio, '337308');
      await tester.pump();
      expect(find.text('${DateTime.now().year}-'), findsOneWidget);

      await tester.enterText(fecha, '15122025');
      await tester.pump();
      expect(find.text('2025-'), findsOneWidget);

      await tester.enterText(fecha, '1512'); // fecha incompleta
      await tester.pump();
      expect(find.text('${DateTime.now().year}-'), findsOneWidget);
    });

    test('anioDelFolio', () {
      final hoy = DateTime(2026, 10, 1);
      expect(Validadores.anioDelFolio('15/12/2025', hoy: hoy), 2025);
      expect(Validadores.anioDelFolio('', hoy: hoy), 2026);
      expect(Validadores.anioDelFolio(null, hoy: hoy), 2026);
      expect(Validadores.anioDelFolio('31/02/2025', hoy: hoy), 2026);
    });
  });

  group('FALLA: el formulario acepta años de pago imposibles', () {
    // parsearFecha acepta cualquier año de 4 dígitos. Con "01/01/0999" la
    // app arma la txca "999-337308" (el año sin ceros) y el servicio
    // responde "El número de transacción no tiene el formato correcto":
    // culpa al folio, que está bien, y no a la fecha. Con "01/01/0000" la
    // txca es "0-337308". El sorteo es de predial 2026; un año fuera de un
    // rango razonable debe rechazarse en el campo de fecha.
    final hoy = DateTime(2026, 10, 1);

    for (final fecha in ['01/01/0000', '01/01/0999', '01/01/1900']) {
      test('"$fecha" no es una fecha de pago válida', () {
        expect(Validadores.validarFechaPago(fecha, hoy: hoy), isNotNull);
      });
    }

    test('GUARDIA: las fechas de pago normales siguen siendo válidas', () {
      expect(Validadores.validarFechaPago('03/09/2026', hoy: hoy), isNull);
      expect(Validadores.validarFechaPago('15/12/2025', hoy: hoy), isNull);
    });
  });

  group('FALLA: el formulario deja pasar un nombre que el servicio rechaza',
      () {
    // El filtro de los nombres permite `\s`, y en Dart (como en JavaScript)
    // `\s` incluye U+FEFF, que llega al pegar texto de Word, Excel o un PDF.
    // trim() de Dart también lo considera espacio, así que el validador lo
    // deja pasar; Python no, y el servicio responde "solo puede contener
    // letras y espacios" sin que el ciudadano vea nada raro en el campo.
    // Prueba gemela en servicio_rifa/tests/test_revision_cuarta_ronda.py.
    //
    // Corregido (1 oct 2026): los tres campos lo quitan con
    // FilteringTextInputFormatter.deny('\uFEFF') antes del filtro de letras.
    testWidgets('U+FEFF pegado en nombre y apellidos no llega al servicio',
        (tester) async {
      final enviados = await montar(tester);
      await llenar(tester, nombre: 'MARÍA\uFEFFJOSÉ', paterno: 'GARCÍA\uFEFF');
      await tester.enterText(find.byType(TextFormField).at(2), '\uFEFFLÓPEZ');
      await tester.pump();
      await tester.tap(find.text('Aceptar'));
      await tester.pumpAndSettle();
      if (find.byType(ConfirmacionDialog).evaluate().isEmpty) {
        return; // el formulario lo detuvo: también es correcto
      }
      await tester.tap(find.text('Aceptar').last);
      await tester.pumpAndSettle();

      final cuerpo = enviados['/api/registrar']!.single;
      for (final campo in ['nombre', 'apellido_paterno', 'apellido_materno']) {
        final valor = cuerpo[campo] as String;
        expect(reNombreDelServicio.hasMatch(valor), isTrue,
            reason: 'Se envió en $campo ${jsonEncode(valor)} (con '
                '${valor.runes.map((r) => 'U+${r.toRadixString(16).toUpperCase().padLeft(4, '0')}').join(' ')})'
                ' y el servicio lo rechaza');
      }
      expect(cuerpo['nombre'], 'MARÍAJOSÉ');
      expect(cuerpo['apellido_paterno'], 'GARCÍA');
      expect(cuerpo['apellido_materno'], 'LÓPEZ');
    });
  });
}
