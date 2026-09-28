import 'package:flutter/material.dart';

/// Reemplazo de BoletoDescarga fuera del navegador (pruebas en la VM).
/// Misma firma que la versión web; no descarga nada y avisa como error.
class BoletoDescarga {
  static Future<void> descargarBoleto({
    required GlobalKey key,
    required String numeroTransaccion,
    required Function(String mensaje, {bool esError}) onNotificar,
  }) async {
    onNotificar(
      'No se pudo descargar el boleto, intenta tomar una captura de pantalla.',
      esError: true,
    );
  }
}
