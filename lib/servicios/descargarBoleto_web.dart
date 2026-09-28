import 'dart:ui' as ui;
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:web/web.dart' as web;
import 'dart:typed_data';

class BoletoDescarga {
  static Future<void> descargarBoleto({
    required GlobalKey key,
    required String numeroTransaccion,
    required Function(String mensaje, {bool esError}) onNotificar,
  }) async {
    onNotificar('Generando tu boleto, por favor espera...');

    try {
      final boundary = key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData == null) {
        throw Exception('No se pudo generar la imagen del boleto.');
      }
      
      final Uint8List pngBytes = byteData!.buffer.asUint8List();
      final blob = web.Blob([pngBytes.toJS].toJS);
      final url = web.URL.createObjectURL(blob);

      web.HTMLAnchorElement()
        ..href = url
        ..download = 'boleto_rifa_octubre_$numeroTransaccion.png'
        ..click();

      web.URL.revokeObjectURL(url);
    } catch (e) {
      onNotificar(
        'No se pudo descargar el boleto, intenta tomar una captura de pantalla.',
        esError: true,
      );
    }
  }
}
