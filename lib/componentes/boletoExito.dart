import 'package:flutter/material.dart';
import 'boleto.dart';
import 'botones.dart';

class BoletoExito extends StatelessWidget {
  final GlobalKey boletoKey;
  final String transaccion;
  final String nombreUsuario;
  final VoidCallback onDescargar;
  final VoidCallback onAceptar;

  const BoletoExito({
    super.key,
    required this.boletoKey,
    required this.transaccion,
    required this.nombreUsuario,
    required this.onDescargar,
    required this.onAceptar,
  });

  @override
Widget build(BuildContext context) {
  final screenWidth = MediaQuery.of(context).size.width;
    return Container(
      width: screenWidth * 0.90,
      constraints: const BoxConstraints(maxWidth: 407),
      padding: EdgeInsets.only(
        top: 40,
        bottom: 22,
        left: screenWidth < 450 ? 16 : 32,
        right: screenWidth < 450 ? 16 : 32,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFE0E0EC),
        borderRadius: BorderRadius.circular(30),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Colors.green,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 40),
          ),
          const SizedBox(height: 16),
          const Text(
            '¡REGISTRO EXITOSO!',
            style: TextStyle(
              color: Color(0xFF4A4A4A),
              fontSize: 24,
              fontFamily: 'Plus Jakarta Sans',
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Tus datos han sido registrados\ncorrectamente.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF4A4A4A),
              fontSize: 15,
              fontFamily: 'Plus Jakarta Sans',
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),

          // envolvemos el boleto para poder transformarlo en imagen
          RepaintBoundary(
            key: boletoKey,
            child: Boleto(
              transaccion: transaccion,
              nombreUsuario: nombreUsuario,
            ),
          ),

          // fecha de la rifa
          const SizedBox(height: 16),
          const Text(
            'La rifa se llevará a cabo el 15 de octubre de 2026.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF4A4A4A),
              fontSize: 14,
              fontFamily: 'Plus Jakarta Sans',
              height: 1.3,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '¡Mucha suerte!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFF4A4A4A),
              fontSize: 14,
              fontFamily: 'Plus Jakarta Sans',
              height: 1.3,
            ),
          ),
          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: SecondaryButton(
                  text: 'Descargar',
                  onPressed: onDescargar,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryButton(
                  text: 'Aceptar',
                  onPressed: onAceptar,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}