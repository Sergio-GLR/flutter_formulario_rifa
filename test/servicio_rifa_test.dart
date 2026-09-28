// Tests del cliente del servicio interno (lib/servicios/servicio_rifa.dart).
// No necesitan el servicio corriendo: las respuestas se simulan con MockClient.
//
//     flutter test test/servicio_rifa_test.dart

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:flutter_formulario_rifa/servicios/servicio_rifa.dart';

final base = Uri.parse('https://rifa.ejemplo.gob.mx/');
final fecha = DateTime(2026, 9, 3);

/// Respuesta JSON como la manda Flask: UTF-8 y SIN charset en Content-Type.
http.Response respuestaJson(Object cuerpo, int status) => http.Response.bytes(
      utf8.encode(jsonEncode(cuerpo)),
      status,
      headers: {'content-type': 'application/json'},
    );

void main() {
  group('validar', () {
    test('envía txca y fecha ISO a /api/validar y devuelve la dirección',
        () async {
      late http.Request enviada;
      final servicio = ServicioRifa(
        base: base,
        cliente: MockClient((req) async {
          enviada = req;
          return respuestaJson({'ok': true, 'direccion': 'CALLE REAL 1'}, 200);
        }),
      );
      final dir =
          await servicio.validar(transaccion: '2026-337308', fechaPago: fecha);

      expect(dir, 'CALLE REAL 1');
      expect(enviada.method, 'POST');
      expect(enviada.url.toString(), 'https://rifa.ejemplo.gob.mx/api/validar');
      expect(jsonDecode(enviada.body),
          {'txca': '2026-337308', 'fecha_pago': '2026-09-03'});
    });

    test('acentos y Ñ llegan bien aunque el servidor no declare charset',
        () async {
      final servicio = ServicioRifa(
        base: base,
        cliente: MockClient(
            (_) async => respuestaJson({'ok': true, 'direccion': 'CALLE ÑANDÚ 12'}, 200)),
      );
      expect(await servicio.validar(transaccion: '2026-1', fechaPago: fecha),
          'CALLE ÑANDÚ 12');
    });

    test('un rechazo muestra el mensaje del servicio', () async {
      const msg = 'No encontramos un pago de predial vigente con ese número.';
      final servicio = ServicioRifa(
        base: base,
        cliente:
            MockClient((_) async => respuestaJson({'ok': false, 'mensaje': msg}, 422)),
      );
      await expectLater(
        servicio.validar(transaccion: '2026-1', fechaPago: fecha),
        throwsA(isA<ErrorServicio>().having((e) => e.mensaje, 'mensaje', msg)),
      );
    });
  });

  group('registrar', () {
    test('envía los datos del ciudadano (sin datos del predio)', () async {
      late Map<String, dynamic> cuerpo;
      final servicio = ServicioRifa(
        base: base,
        cliente: MockClient((req) async {
          cuerpo = jsonDecode(req.body);
          expect(req.url.path, '/api/registrar');
          return respuestaJson({
            'ok': true,
            'mensaje': 'Registro completado exitosamente.',
            'boleto': {'txca': '2026-337308', 'nombre': 'ANA LÓPEZ'},
          }, 200);
        }),
      );
      final boleto = await servicio.registrar(
        transaccion: '2026-337308',
        fechaPago: fecha,
        nombre: 'ANA',
        apellidoPaterno: 'LÓPEZ',
        apellidoMaterno: '',
        telefono: '6181234567',
      );

      expect(boleto.nombre, 'ANA LÓPEZ');
      expect(cuerpo, {
        'txca': '2026-337308',
        'fecha_pago': '2026-09-03',
        'nombre': 'ANA',
        'apellido_paterno': 'LÓPEZ',
        'apellido_materno': null, // vacío se manda como null
        'telefono': '6181234567',
      });
      for (final prohibido in ['clave_catastral', 'propietario', 'direccion']) {
        expect(cuerpo.containsKey(prohibido), isFalse,
            reason: 'La app no debe enviar $prohibido: lo decide el servicio');
      }
    });
  });

  group('errores', () {
    Future<String> mensajeCon(MockClient cliente) async {
      try {
        await ServicioRifa(base: base, cliente: cliente)
            .validar(transaccion: '2026-1', fechaPago: fecha);
        return 'sin error';
      } on ErrorServicio catch (e) {
        return e.mensaje;
      }
    }

    test('sin conexión: mensaje amigable, nunca el error técnico', () async {
      final msg = await mensajeCon(MockClient(
          (_) async => throw http.ClientException('XMLHttpRequest error.')));
      expect(msg, ServicioRifa.msgSinConexion);
    });

    test('respuesta que no es JSON (página de error del proxy)', () async {
      final msg = await mensajeCon(MockClient(
          (_) async => http.Response('<html>502 Bad Gateway</html>', 502)));
      expect(msg, ServicioRifa.msgInesperado);
    });

    test('JSON sin mensaje o con forma inesperada', () async {
      expect(await mensajeCon(MockClient((_) async => respuestaJson({'ok': false}, 500))),
          ServicioRifa.msgInesperado);
      expect(await mensajeCon(MockClient((_) async => respuestaJson([1, 2], 200))),
          ServicioRifa.msgInesperado);
      expect(
          await mensajeCon(
              MockClient((_) async => respuestaJson({'ok': true, 'direccion': 5}, 200))),
          ServicioRifa.msgInesperado);
    });
  });
}
