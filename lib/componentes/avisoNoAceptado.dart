import 'package:flutter/material.dart';
import 'botones.dart';

class AvisoNoAceptado extends StatelessWidget {
  final VoidCallback onRevisarTerminos;


  const AvisoNoAceptado({
    super.key,
    required this.onRevisarTerminos,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 512),
      child: Container(
        padding: const EdgeInsets.all(40),
        decoration: ShapeDecoration(
          color: const Color(0xFFF8F7FC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          shadows: const [
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
            const Icon(
              Icons.privacy_tip_outlined,
              size: 64,
              color: Color(0xFF6B6B80),
            ),
            const SizedBox(height: 24),
            const Text(
              'Aviso de Privacidad Requerido',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF1A1A2E),
                fontSize: 20,
                fontFamily: 'Plus Jakarta Sans',
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Para poder registrarte en la rifa, es estrictamente necesario aceptar el aviso de privacidad y términos para el manejo de los datos catastrales y personales.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF4A4A4A),
                fontSize: 14,
                fontFamily: 'Plus Jakarta Sans',
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: 250, // Un botón más pequeño y centrado
              child: PrimaryButton(
                text: 'Revisar Términos',
                onPressed: onRevisarTerminos,
              ),
            ),
          ],
        ),
      ),
    );
  }
}