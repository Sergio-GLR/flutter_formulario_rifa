// Tests de la revisión crítica del formulario (24 sep 2026).
//
// Cómo correrlos, desde la carpeta flutter_formulario_rifa:
//     flutter test test/revision_test.dart
//
// Convención (igual que en script_boletos):
//   * group 'FALLA ...'   -> documenta un defecto encontrado. HOY FALLA a
//     propósito; debe pasar cuando se corrija.
//   * group 'GUARDIA ...' -> comportamiento correcto hoy. HOY PASA; sirve para
//     detectar regresiones mientras se hacen las correcciones.
//
// No necesitan Supabase ni la API del municipio: prueban el formulario y los
// validadores por separado.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_formulario_rifa/componentes/tarjetaFormulario.dart';
import 'package:flutter_formulario_rifa/validadores/validadores.dart';

// Orden de los campos en TarjetaFormulario
const int kNombre = 0;
const int kApellidoPaterno = 1;
const int kApellidoMaterno = 2;
const int kTelefono = 3;
const int kTransaccion = 4;

/// Monta la tarjeta del formulario sola (sin Supabase ni API) y devuelve la
/// llave del Form para poder validarlo.
Future<GlobalKey<FormState>> montarFormulario(WidgetTester tester) async {
  final formKey = GlobalKey<FormState>();
  final ctrls = List.generate(5, (_) => TextEditingController());
  final focus = FocusNode();
  addTearDown(() {
    for (final c in ctrls) {
      c.dispose();
    }
    focus.dispose();
  });

  // Pantalla alta para que el formulario completo quepa sin desbordarse
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TarjetaFormulario(
            formKey: formKey,
            nombreCtrl: ctrls[kNombre],
            apellidoPaternoCtrl: ctrls[kApellidoPaterno],
            apellidoMaternoCtrl: ctrls[kApellidoMaterno],
            telefonoCtrl: ctrls[kTelefono],
            transaccionCtrl: ctrls[kTransaccion],
            transaccionFocus: focus,
            isCargando: false,
            onAceptar: () {},
            onCancelar: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return formKey;
}

Finder campo(int indice) => find.byType(TextFormField).at(indice);

/// Escribe en un campo pasando por sus inputFormatters, como lo haría el usuario.
Future<void> escribir(WidgetTester tester, int indice, String texto) async {
  await tester.enterText(campo(indice), texto);
  await tester.pump();
}

/// Texto que quedó en el campo después de los formatters.
String textoDe(WidgetTester tester, int indice) {
  final editable = find.descendant(
    of: campo(indice),
    matching: find.byType(EditableText),
  );
  return tester.widget<EditableText>(editable).controller.text;
}

/// Llena todos los campos con datos válidos, cambiando los que se indiquen.
Future<void> llenarFormulario(
  WidgetTester tester, {
  String nombre = 'MARIA FERNANDA',
  String paterno = 'GARCIA',
  String materno = 'LOPEZ',
  String telefono = '6181234567',
  String transaccion = '337308',
}) async {
  await escribir(tester, kNombre, nombre);
  await escribir(tester, kApellidoPaterno, paterno);
  await escribir(tester, kApellidoMaterno, materno);
  await escribir(tester, kTelefono, telefono);
  await escribir(tester, kTransaccion, transaccion);
}

void main() {
  // ===================================================== FALLAS (hoy fallan)
  group('FALLA: regresión de la refactorización', () {
    // tarjetaFormulario.dart, campo NOMBRE: usa Validadores.validarTransaccion
    // (mínimo 6 caracteres, mensaje "Faltan dígitos") en lugar de
    // validarRequerido. Nadie con un nombre de 5 letras o menos puede
    // registrarse.
    for (final nombre in ['ANA', 'LUIS', 'JOSÉ', 'RAÚL', 'EVA']) {
      testWidgets('el nombre "$nombre" es válido', (tester) async {
        final formKey = await montarFormulario(tester);
        await llenarFormulario(tester, nombre: nombre);

        expect(formKey.currentState!.validate(), isTrue,
            reason: 'El formulario rechazó el nombre "$nombre"');
        await tester.pump();
        expect(find.text('Faltan dígitos'), findsNothing,
            reason: 'Apareció "Faltan dígitos" en un campo de nombre');
      });
    }
  });

  group('FALLA: el formulario rechaza a personas válidas', () {
    testWidgets('se puede escribir la Ü (GÜERECA, ARGÜELLES)', (tester) async {
      await montarFormulario(tester);
      await escribir(tester, kApellidoPaterno, 'GÜERECA');
      expect(textoDe(tester, kApellidoPaterno), 'GÜERECA',
          reason: 'El formatter quitó la Ü del apellido');
    });

    testWidgets('el apellido materno es opcional', (tester) async {
      final formKey = await montarFormulario(tester);
      await llenarFormulario(tester, materno: '');
      expect(formKey.currentState!.validate(), isTrue,
          reason: 'Una persona con un solo apellido no puede registrarse');
    });
  });

  group('FALLA: secretos dentro de la app', () {
    // Flutter publica todo lo declarado en "assets" junto con la app.
    test('pubspec.yaml no declara .env como asset', () {
      final lineas = File('pubspec.yaml').readAsLinesSync();
      final declarado = lineas.any((l) => l.trim() == '- .env');
      expect(declarado, isFalse,
          reason: '.env se empaqueta con la app y cualquiera puede descargarlo');
    });

    // El token y el salt del SRM deben vivir solo en el servicio interno.
    test('el código de la app no usa el token ni el salt del SRM', () {
      final usos = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is File && f.path.endsWith('.dart')) {
          final codigo = f.readAsStringSync();
          if (codigo.contains('API_SRM_TOKEN') ||
              codigo.contains('API_SRM_SECRET')) {
            usos.add(f.path);
          }
        }
      }
      expect(usos, isEmpty,
          reason: 'Estos archivos leen secretos del SRM desde la app: $usos');
    });
  });

  // ==================================================== GUARDIAS (hoy pasan)
  group('GUARDIA: validadores', () {
    test('validarRequerido', () {
      expect(Validadores.validarRequerido('ANA'), isNull);
      expect(Validadores.validarRequerido(''), 'Campo requerido');
      expect(Validadores.validarRequerido('   '), 'Campo requerido');
      expect(Validadores.validarRequerido(null), 'Campo requerido');
    });

    test('validarTelefono exige 10 dígitos', () {
      expect(Validadores.validarTelefono('6181234567'), isNull);
      expect(Validadores.validarTelefono('618123456'), 'Debe contener 10 dígitos');
      expect(Validadores.validarTelefono(''), 'Campo requerido');
    });

    test('validarTransaccion exige 6 dígitos', () {
      expect(Validadores.validarTransaccion('337308'), isNull);
      expect(Validadores.validarTransaccion('33730'), 'Faltan dígitos');
      expect(Validadores.validarTransaccion(''), 'Campo requerido');
    });
  });

  group('GUARDIA: formulario', () {
    testWidgets('un registro con datos normales es válido', (tester) async {
      final formKey = await montarFormulario(tester);
      await llenarFormulario(tester);
      expect(formKey.currentState!.validate(), isTrue);
    });

    testWidgets('los nombres se convierten a mayúsculas', (tester) async {
      await montarFormulario(tester);
      await escribir(tester, kApellidoPaterno, 'garcía');
      expect(textoDe(tester, kApellidoPaterno), 'GARCÍA');
    });

    testWidgets('no se permiten espacios dobles ni al inicio', (tester) async {
      await montarFormulario(tester);
      await escribir(tester, kApellidoPaterno, ' GARCIA');
      expect(textoDe(tester, kApellidoPaterno), '');
      await escribir(tester, kApellidoPaterno, 'DE LA ROSA');
      await escribir(tester, kApellidoPaterno, 'DE  LA ROSA');
      expect(textoDe(tester, kApellidoPaterno), 'DE LA ROSA');
    });

    testWidgets('teléfono y transacción solo aceptan dígitos y su longitud',
        (tester) async {
      await montarFormulario(tester);
      await escribir(tester, kTelefono, '618-123-4567-99');
      expect(textoDe(tester, kTelefono), '6181234567');
      await escribir(tester, kTransaccion, '12a34567');
      expect(textoDe(tester, kTransaccion), '123456');
    });

    testWidgets('campos vacíos no pasan', (tester) async {
      final formKey = await montarFormulario(tester);
      expect(formKey.currentState!.validate(), isFalse);
    });
  });
}
