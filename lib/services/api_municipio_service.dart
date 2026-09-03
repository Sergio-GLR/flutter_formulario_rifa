import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:crypto/crypto.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class ApiMunicipioService {
  Future<Map<String, String>> validarTransaccion(String transaccion) async {
    final baseUrl = dotenv.env['API_SRM_URL']!;
    final token = dotenv.env['API_SRM_TOKEN']!;
    final secretSalt = dotenv.env['API_SRM_SECRET']!;

    final endpoint = Uri.parse('$baseUrl/Pr_sorteo');

    // Concatenación directa de nuestro algoritmo del signature (según la sección 4.2)
    final dataToHash = transaccion + token;

    // Generación de la firma HMAC-SHA256 (usando el salt en ASCII/UTF-8)
    final keyBytes = utf8.encode(secretSalt);
    final dataBytes = utf8.encode(dataToHash);
    final hmac = Hmac(sha256, keyBytes);

    // .toString() en la librería crypto de Dart devuelve el hash en hexadecimal minúsculas
    final signature = hmac.convert(dataBytes).toString();

    // Lógica de 1 reintento máximo (sección 10)
    int intentos = 0;

    while (intentos < 2) {
      try {
        final response = await http
            .post(
              endpoint,
              headers: {
                'Content-Type': 'application/json',
                'Accept': 'application/json',
              },
              body: jsonEncode({
                'txca': transaccion,
                'signature': signature,
                'token': token,
              }),
            )
            .timeout(
              const Duration(seconds: 12),
            ); // Timeout de 12 segundos (rango sugerido 8-15s)

        final jsonResponse = jsonDecode(response.body);

        // Manejo del objeto de error oficial de la API del municipio
        if (jsonResponse.containsKey('error')) {
          throw Exception(jsonResponse['error']['mensaje']);
        }

        // Manejo de la respuesta de éxito
        if (jsonResponse.containsKey('response')) {
          final data = jsonResponse['response'];

          // Regla de negocio: Solo personas FÍSICAS
          if (data['t_persona'] != 'FISICA') {
            throw Exception('El sorteo es exclusivo para personas físicas.');
          }

          // Retornamos mapeando a los nombres de variables que ya usamos en el formulario
          return {
            'direccion': data['domicilio'],
            'claveCatastral': data['cc'],
            'propietario': data['propietario'],
          };
        }

        throw Exception('Estructura de respuesta desconocida.');
      } on TimeoutException catch (_) {
        if (intentos == 1)
          throw Exception(
            'El servidor tardó demasiado en responder. Intenta de nuevo.',
          );
        intentos++;
      } on SocketException catch (_) {
        if (intentos == 1)
          throw Exception(
            'Error de red. Verifica que estés conectado a la red municipal.',
          );
        intentos++;
      } catch (e) {
        if (e is Exception && e.toString().startsWith('Exception: ')) {
          rethrow; // Errores de negocio (no se reintentan)
        }
        if (intentos == 1)
          throw Exception('Error de conexión con el servidor.');
        intentos++;
      }
    }

    throw Exception('Error inesperado al contactar al servidor.');
  }
}
