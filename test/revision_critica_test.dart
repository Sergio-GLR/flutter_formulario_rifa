// Revisión crítica del formulario (28 sep 2026).
//
//     flutter test test/revision_critica_test.dart
//
// Cada prueba documenta un defecto o un supuesto frágil encontrado al intentar
// romper la app. Fallaban con el código de la revisión y pasan conforme se
// corrige cada defecto; ya corregidas, se quedan como protección para que el
// defecto no regrese.
//
// Convención (igual que en revision_test.dart):
//   * group 'FALLA ...'    -> defecto confirmado.
//   * group 'SUPUESTO ...' -> el código asume algo que no está garantizado;
//                             hay que confirmarlo antes de decidir.
//
// La PANTALLA completa se monta con un ServicioRifa simulado (MockClient):
// así se ve exactamente qué envía la app, sin servidor.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_formulario_rifa/componentes/boleto.dart';
import 'package:flutter_formulario_rifa/componentes/tarjetaFormulario.dart';
import 'package:flutter_formulario_rifa/pantallas/formulario_screen.dart';
import 'package:flutter_formulario_rifa/servicios/servicio_rifa.dart';
import 'package:flutter_formulario_rifa/validadores/validadores.dart';

/// Monta la tarjeta del formulario sola y devuelve la llave del Form.
Future<GlobalKey<FormState>> montarFormulario(
  WidgetTester tester,
  List<TextEditingController> ctrls,
) async {
  final formKey = GlobalKey<FormState>();
  final focus = FocusNode();
  addTearDown(() {
    for (final c in ctrls) {
      c.dispose();
    }
    focus.dispose();
  });
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: TarjetaFormulario(
            formKey: formKey,
            nombreCtrl: ctrls[0],
            apellidoPaternoCtrl: ctrls[1],
            apellidoMaternoCtrl: ctrls[2],
            telefonoCtrl: ctrls[3],
            transaccionCtrl: ctrls[4],
            fechaPagoCtrl: ctrls[5],
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

Future<void> escribir(WidgetTester tester, int indice, String texto) async {
  await tester.enterText(find.byType(TextFormField).at(indice), texto);
  await tester.pump();
}

/// Monta la pantalla completa con un servicio simulado, acepta términos,
/// llena el formulario y confirma. Devuelve lo que la app envió:
/// (ruta, cuerpo JSON) por cada llamada.
Future<List<(String, Map<String, dynamic>)>> registrarEnPantalla(
  WidgetTester tester,
  String fechaPago,
) async {
  final enviadas = <(String, Map<String, dynamic>)>[];
  final servicio = ServicioRifa(
    base: Uri.parse('https://rifa.ejemplo.gob.mx/'),
    cliente: MockClient((req) async {
      final cuerpo = jsonDecode(req.body) as Map<String, dynamic>;
      enviadas.add((req.url.path, cuerpo));
      final respuesta = req.url.path == '/api/validar'
          ? {'ok': true, 'direccion': 'CALLE OFICIAL 120'}
          : {
              'ok': true,
              'mensaje': 'Registro completado exitosamente.',
              // Como el servicio real: devuelve la txca que recibió
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

  final campos = find.byType(TextFormField);
  for (final (i, texto) in [
    (0, 'ANA'),
    (1, 'GARCIA'),
    (3, '6181234567'),
    (4, '337308'),
    (5, fechaPago),
  ]) {
    await tester.enterText(campos.at(i), texto);
  }
  await tester.pump();
  await tester.tap(find.text('Aceptar')); // enviar -> /api/validar
  await tester.pumpAndSettle();
  await tester.tap(find.text('Aceptar').last); // confirmar dirección -> /api/registrar
  await tester.pumpAndSettle();
  return enviadas;
}

void main() {
  group('FALLA: los validadores confían en que el formatter ya filtró', () {
    // validarTelefono y validarTransaccion solo miden el largo. Hoy los
    // salva el inputFormatter, pero cualquier otro camino (autocompletar del
    // navegador, pegar en un campo sin formatter, reutilizar el validador)
    // deja pasar letras.
    test('validarTelefono rechaza lo que no son 10 dígitos', () {
      expect(Validadores.validarTelefono('abcdefghij'), isNotNull);
      expect(Validadores.validarTelefono('618-123-45'), isNotNull);
      expect(Validadores.validarTelefono('61812345678'), isNotNull,
          reason: 'Aceptó 11 dígitos; el servicio los rechaza');
    });

    test('validarTransaccion rechaza lo que no son dígitos', () {
      expect(Validadores.validarTransaccion('abcdef'), isNotNull);
      expect(Validadores.validarTransaccion('12 456'), isNotNull);
    });
  });

  group('FALLA: el formulario acepta lo que el servicio rechaza', () {
    // El servicio (app.py, LARGO_MAX_NOMBRE = 60) rechaza nombres de más de
    // 60 letras, pero el formulario no pone límite: el ciudadano llena todo,
    // confirma su dirección y hasta el final recibe un error (y además con
    // un mensaje que no habla del largo).
    testWidgets('un nombre de más de 60 letras no pasa el formulario',
        (tester) async {
      final ctrls = List.generate(6, (_) => TextEditingController());
      final formKey = await montarFormulario(tester, ctrls);
      await escribir(tester, 0, 'A' * 61);
      await escribir(tester, 1, 'GARCIA');
      await escribir(tester, 3, '6181234567');
      await escribir(tester, 4, '337308');
      await escribir(tester, 5, '03092026');

      final largo = ctrls[0].text.length;
      final valido = formKey.currentState!.validate();
      expect(largo <= 60 || !valido, isTrue,
          reason: 'El formulario aceptó un nombre de $largo letras');
    });
  });

  group('SUPUESTO: número de transacción de exactamente 6 dígitos', () {
    // El formulario obliga a 6 dígitos (LengthLimiting(6) + mínimo 6), pero
    // el servicio acepta de 1 a 10 (app.py RE_TXCA) y el propio comentario
    // dice que el SRM acepta ^\d{4}-\d+$. Si el SRM llega al folio 1000000
    // o emite folios cortos a inicio de año, esas personas no pueden
    // registrarse. Confirmar con el SRM el formato real del folio.
    testWidgets('el campo permite escribir 7 dígitos', (tester) async {
      final ctrls = List.generate(6, (_) => TextEditingController());
      await montarFormulario(tester, ctrls);
      await escribir(tester, 4, '1234567');
      expect(ctrls[4].text, '1234567');
    });
  });

  group('SUPUESTO: la app vive en la raíz del dominio', () {
    // _post usa _base.resolve('/api/...') con diagonal inicial: descarta
    // cualquier subcarpeta. Si la app se publica en
    // https://municipio.gob.mx/rifa/ (o API_BASE apunta a .../rifa/), las
    // llamadas van a https://municipio.gob.mx/api/... y no al servicio.
    test('respeta la subcarpeta de la URL base', () async {
      late Uri llamada;
      final servicio = ServicioRifa(
        base: Uri.parse('https://municipio.gob.mx/rifa/'),
        cliente: MockClient((req) async {
          llamada = req.url;
          return http.Response.bytes(
            utf8.encode(jsonEncode({'ok': true, 'direccion': 'X'})),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      await servicio.validar(
          transaccion: '2026-337308', fechaPago: DateTime(2026, 9, 3));
      expect(llamada.toString(), 'https://municipio.gob.mx/rifa/api/validar');
    });
  });

  group('FALLA: el año del folio sale del reloj del equipo', () {
    // formulario_screen.dart armaba la txca como
    //   '${DateTime.now().year}-${_transaccionCtrl.text}'
    // Quien pagó el 30 de diciembre y se registra en enero mandaba el folio
    // con el año equivocado (el SRM lo rechaza, o es el folio de otra
    // persona). Igual si el reloj del módulo está mal. La pantalla de éxito
    // repetía el cálculo, así que corregir solo el envío no bastaba.
    final anioPasado = DateTime.now().year - 1;
    final fechaDiciembre = '3012$anioPasado'; // 30/12 del año pasado

    testWidgets('la txca enviada usa el año de la fecha de pago',
        (tester) async {
      final enviadas = await registrarEnPantalla(tester, fechaDiciembre);

      expect(enviadas.map((e) => e.$1), ['/api/validar', '/api/registrar']);
      for (final (_, cuerpo) in enviadas) {
        expect(cuerpo['txca'], '$anioPasado-337308');
        expect(cuerpo['fecha_pago'], '$anioPasado-12-30');
      }
    });

    testWidgets('el boleto muestra el folio que se registró', (tester) async {
      await registrarEnPantalla(tester, fechaDiciembre);

      final boleto = find.byType(Boleto);
      expect(boleto, findsOneWidget, reason: 'No apareció el boleto');
      expect(tester.widget<Boleto>(boleto).transaccion,
          '$anioPasado-337308');
    });
  });

  group('FALLA: la suite de Flutter no puede quedar en verde', () {
    // test/widget_test.dart es la prueba del contador de la plantilla de
    // Flutter (busca '0', '1' y un botón +) y además no compila: importa
    // main.dart -> formulario_screen.dart -> descargarBoleto.dart ->
    // dart:js_interop. `flutter test` siempre sale en rojo, lo que esconde
    // cualquier regresión real, y ninguna prueba puede montar la pantalla.
    test('main.dart no arrastra dart:js_interop en la VM', () {
      // Recorre los imports de la app desde main.dart. De un import
      // condicional solo sigue la opción por defecto (la que usa la VM).
      final raiz = Directory('lib').absolute.path;
      final vistos = <String>{};
      final cadena = <String, String>{}; // archivo -> quién lo importó
      final pendientes = ['$raiz${Platform.pathSeparator}main.dart'];
      String? culpable;
      final reImport = RegExp(r'''^(?:import|export)\s+['"]([^'"]+)['"]''');

      while (pendientes.isNotEmpty && culpable == null) {
        final ruta = pendientes.removeLast();
        if (!vistos.add(ruta)) continue;
        for (final linea in File(ruta).readAsLinesSync()) {
          final uri = reImport.firstMatch(linea.trim())?.group(1);
          if (uri == null) continue;
          if (uri == 'dart:js_interop' || uri.startsWith('package:web/')) {
            culpable = ruta;
            break;
          }
          String? destino;
          if (uri.startsWith('package:flutter_formulario_rifa/')) {
            destino = '$raiz/${uri.substring(32)}';
          } else if (!uri.contains(':')) {
            destino = File(ruta).parent.uri.resolve(uri).toFilePath();
          }
          if (destino != null) {
            destino = File(destino).absolute.path;
            cadena.putIfAbsent(destino, () => ruta);
            pendientes.add(destino);
          }
        }
      }

      final ruta = <String>[];
      for (var r = culpable; r != null; r = cadena[r]) {
        ruta.insert(0, r.substring(raiz.length + 1));
      }
      expect(culpable, isNull,
          reason: 'dart:js_interop llega a la VM por: ${ruta.join(' -> ')}');
    });
  });
}
