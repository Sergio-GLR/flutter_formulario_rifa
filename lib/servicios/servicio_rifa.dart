import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// Error con un mensaje listo para mostrar al ciudadano.
class ErrorServicio implements Exception {
  final String mensaje;
  const ErrorServicio(this.mensaje);

  @override
  String toString() => mensaje;
}

class BoletoRegistrado {
  final String txca;
  final String nombre;
  const BoletoRegistrado({required this.txca, required this.nombre});
}

/// Cliente del servicio interno (servicio_rifa). La app ya NO habla con el
/// SRM ni con Supabase: todo pasa por aquí, y el servicio guarda los secretos.
class ServicioRifa {
  /// Vacío = el mismo servidor que sirve la app (producción).
  /// Para desarrollo local:
  ///   flutter run -d chrome --dart-define=API_BASE=http://localhost:8080
  static const String _apiBase = String.fromEnvironment('API_BASE');

  /// El servicio puede tardar hasta ~25 s si el SRM está lento (reintenta 1 vez).
  static const Duration _timeout = Duration(seconds: 45);

  static const String msgSinConexion =
      'No pudimos conectar con el servidor. Revisa tu conexión e intenta de nuevo.';
  static const String msgTardanza =
      'El servidor tardó demasiado en responder. Intenta de nuevo.';
  static const String msgInesperado =
      'Ocurrió un error inesperado. Intenta de nuevo más tarde.';

  final http.Client _cliente;
  final Uri _base;

  ServicioRifa({http.Client? cliente, Uri? base})
      : _cliente = cliente ?? http.Client(),
        _base = base ?? (_apiBase.isEmpty ? Uri.base : Uri.parse(_apiBase));

  /// Devuelve la dirección del predio para que el ciudadano la confirme.
  Future<String> validar({
    required String transaccion,
    required DateTime fechaPago,
  }) async {
    final datos = await _post('validar', {
      'txca': transaccion,
      'fecha_pago': _fechaIso(fechaPago),
    });
    final direccion = datos['direccion'];
    if (direccion is! String) throw const ErrorServicio(msgInesperado);
    return direccion;
  }

  Future<BoletoRegistrado> registrar({
    required String transaccion,
    required DateTime fechaPago,
    required String nombre,
    required String apellidoPaterno,
    required String apellidoMaterno,
    required String telefono,
  }) async {
    final datos = await _post('registrar', {
      'txca': transaccion,
      'fecha_pago': _fechaIso(fechaPago),
      'nombre': nombre,
      'apellido_paterno': apellidoPaterno,
      'apellido_materno': apellidoMaterno.isEmpty ? null : apellidoMaterno,
      'telefono': telefono,
    });
    final boleto = datos['boleto'];
    if (boleto is! Map ||
        boleto['txca'] is! String ||
        boleto['nombre'] is! String) {
      throw const ErrorServicio(msgInesperado);
    }
    return BoletoRegistrado(txca: boleto['txca'], nombre: boleto['nombre']);
  }

  static String _fechaIso(DateTime f) =>
      '${f.year.toString().padLeft(4, '0')}-'
      '${f.month.toString().padLeft(2, '0')}-'
      '${f.day.toString().padLeft(2, '0')}';

  Future<Map<String, dynamic>> _post(
    String ruta,
    Map<String, dynamic> cuerpo,
  ) async {
    late final http.Response respuesta;
    try {
      respuesta = await _cliente
          .post(
            _base.resolve('/api/$ruta'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(cuerpo),
          )
          .timeout(_timeout);
    } on TimeoutException {
      throw const ErrorServicio(msgTardanza);
    } catch (_) {
      throw const ErrorServicio(msgSinConexion);
    }

    Map<String, dynamic> datos = {};
    try {
      // bodyBytes + utf8: el servidor no declara charset y `respuesta.body`
      // decodificaría como Latin-1 (acentos y Ñ rotos).
      final decodificado = jsonDecode(utf8.decode(respuesta.bodyBytes));
      if (decodificado is Map<String, dynamic>) datos = decodificado;
    } catch (_) {
      // Respuesta que no es JSON (por ejemplo, una página de error del proxy)
    }

    if (datos['ok'] == true) return datos;
    final mensaje = datos['mensaje'];
    throw ErrorServicio(
      mensaje is String && mensaje.isNotEmpty ? mensaje : msgInesperado,
    );
  }
}
