import 'package:flutter/material.dart';
import 'botones.dart';

class TerminosCondicionesDialog extends StatelessWidget {
  final VoidCallback onAceptar;
  final VoidCallback onRechazar;

  const TerminosCondicionesDialog({
    super.key,
    required this.onAceptar,
    required this.onRechazar,
});

  @override
  Widget build(BuildContext context) {
    return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 600, // Evita que se deforme o estire en pantallas de PC
              maxHeight: 600,
            ),
            padding: const EdgeInsets.all(32),
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Color(0xFF1A1A2E),
                      size: 28,
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Aviso de Privacidad y Términos',
                        style: TextStyle(
                          color: Color(0xFF1A1A2E),
                          fontSize: 20,
                          fontFamily: 'Plus Jakarta Sans',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.black12, height: 1),
                const SizedBox(height: 16),

                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      'De conformidad con la Ley de Protección de Datos Personales en Posesión de Sujetos Obligados del Estado, el Municipio de Durango informa:\n\n'
                      '1. Los datos recabados en este formulario así como la información catastral asociada a la transacción, '
                      'serán utilizados única y exclusivamente para el registro, validación y contacto de los participantes de la Rifa Predial - Octubretón.\n\n'
                      '2. Para que el registro sea válido, la transacción ingresada debe corresponder a un pago validado por el sistema de recaudación.\n\n'
                      '3. El manejo de la información se realiza bajo estrictos protocolos de seguridad para proteger la privacidad del propietario del inmueble.\n\n'
                      'Al hacer clic en "Aceptar", usted consiente el tratamiento de sus datos personales para los fines previamente descritos.',
                      style: const TextStyle(
                        color: Color(0xFF4A4A4A),
                        fontSize: 14,
                        fontFamily: 'Plus Jakarta Sans',
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        text: 'No Acepto',
                        onPressed: onRechazar,
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
          ),
        );
      }
  }