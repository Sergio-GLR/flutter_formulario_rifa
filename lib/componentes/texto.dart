import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextField extends StatelessWidget {
  final String label;
  final String hint;
  final String helper;
  final TextEditingController controller;
  final bool enabled;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final FocusNode? focusNode;
  final String? prefixText;
  final String? Function(String?)? validator; // propiedad para validar
  final ValueChanged<String>?
  onFieldSubmitted; // variable para manejar el evento de envío del campo
  final TextInputAction? textInputAction; // accion del teclado

  const CustomTextField({
    required this.label,
    required this.hint,
    required this.helper,
    required this.controller,
    this.enabled = true,
    this.keyboardType,
    this.inputFormatters,
    this.textCapitalization = TextCapitalization.none,
    this.focusNode,
    this.prefixText,
    this.validator,
    this.onFieldSubmitted,
    this.textInputAction,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF6B6B80),
            fontSize: 12,
            fontFamily: 'Plus Jakarta Sans',
            fontWeight: FontWeight.w600,
            letterSpacing: 0.72,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textCapitalization: textCapitalization,
          validator: validator, // Le pasamos el validador
          onFieldSubmitted: onFieldSubmitted, // Lo pasamos al TextFormField
          textInputAction:
              textInputAction ??
              TextInputAction.next, // Por defecto pasa al siguiente
          autovalidateMode: AutovalidateMode
              .onUserInteraction, // Valida conforme el usuario escribe
          style: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontSize: 14,
            fontFamily: 'Plus Jakarta Sans',
          ),
          decoration: InputDecoration(
            hintText: hint,
            prefixText: prefixText,
            helperText: helper, // Flutter maneja el helper nativamente
            helperStyle: const TextStyle(
              color: Color(0xFFAAAABC),
              fontSize: 12,
              fontFamily: 'Plus Jakarta Sans',
            ),
            errorStyle: const TextStyle(
              color: Color(0xFFEB5757),
              fontSize: 12,
              fontFamily: 'Plus Jakarta Sans',
            ),
            prefixStyle: const TextStyle(
              color: Color(0xFF1A1A2E),
              fontSize: 14,
              fontFamily: 'Plus Jakarta Sans',
              fontWeight: FontWeight.w600,
            ),
            hintStyle: const TextStyle(color: Color(0x7F1A1A2E)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE0E0EC)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFC4B5FD)),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEB5757)),
            ),
            focusedErrorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFEB5757)),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE0E0EC)),
            ),
          ),
        ),
      ],
    );
  }
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class SingleSpaceTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Bloquea cualquier intento de poner un espacio al inicio o dos espacios seguidos
    if (newValue.text.startsWith(' ') || newValue.text.contains('  ')) {
      return oldValue;
    }
    return newValue;
  }
}