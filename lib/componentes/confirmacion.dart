import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'botones.dart';

class ConfirmacionDialog extends StatelessWidget {
  final String transaccion;
  final String direccion;
  final VoidCallback onCancelar;
  final VoidCallback onConfirmar;

  const ConfirmacionDialog({
    super.key,
    required this.transaccion,
    required this.direccion,
    required this.onCancelar,
    required this.onConfirmar,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          // El widget Focus con autofocus captura los eventos del teclado globalmente
          child: Focus(
            autofocus: true,
            onKeyEvent: (FocusNode node, KeyEvent event) {
              // Si el usuario presiona la tecla Enter, confirmamos el modal
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter) {
                onConfirmar();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Container(
              width: MediaQuery.of(context).size.width * 0.9,
              constraints: const BoxConstraints(maxWidth: 593),
              padding: const EdgeInsets.only(
                top: 40,
                bottom: 27,
                left: 32,
                right: 32,
              ),
              decoration: ShapeDecoration(
                color: const Color(0xFFD9D9D9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      // Estilo base para todo el texto (normal)
                      style: const TextStyle(
                        color: Color(0xFF4A4A4A),
                        fontSize: 18,
                        fontFamily: 'Plus Jakarta Sans',
                        fontWeight: FontWeight.w400,
                        height: 1.3,
                      ),
                      children: [
                        const TextSpan(text: 'El número de transacción '),
                        // Estilo sobrescrito para poner en negritas solo la transacción
                        TextSpan(
                          text: transaccion,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: ' está asociado a la siguiente dirección:\n\n$direccion\n\n¿Es correcta la dirección?',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      // Botón principal restaurado a la izquierda
                      Expanded(
                        child: PrimaryButton(
                          text: 'Aceptar',
                          onPressed: onConfirmar,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Botón secundario restaurado a la derecha
                      Expanded(
                        child: SecondaryButton(
                          text: 'Cancelar',
                          onPressed: onCancelar,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
  }
}