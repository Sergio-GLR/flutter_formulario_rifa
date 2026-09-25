import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'botones.dart';
import 'texto.dart';

import '../validadores/validadores.dart';

class TarjetaFormulario extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nombreCtrl;
  final TextEditingController apellidoPaternoCtrl;
  final TextEditingController apellidoMaternoCtrl;
  final TextEditingController telefonoCtrl;
  final TextEditingController transaccionCtrl;
  final FocusNode transaccionFocus;
  final bool isCargando;
  final VoidCallback onAceptar;
  final VoidCallback onCancelar;

  const TarjetaFormulario({
    super.key,
    required this.formKey,
    required this.nombreCtrl,
    required this.apellidoPaternoCtrl,
    required this.apellidoMaternoCtrl,
    required this.telefonoCtrl,
    required this.transaccionCtrl,
    required this.transaccionFocus,
    required this.isCargando,
    required this.onAceptar,
    required this.onCancelar,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 512),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: const Color(0xFFF8F7FC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          // sombra mas suave de fondo
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
            // linea decorativa
            Container(
              height: 6,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Color(0xFF6B6B80),
                    Color(0xFFA0A0AC),
                    Color(0xFFAAAABC),
                  ],
                ),
              ),
            ),
            // encabezado institucional primero
            Container(
              padding: const EdgeInsets.only(
                top: 32,
                left: 32,
                right: 32,
                bottom: 24,
              ),
              child: Row(
                children: [
                  Container(
                    width: 104,
                    height: 64,
                    decoration: const BoxDecoration(
                      image: DecorationImage(
                        image: AssetImage("assets/images/logo_durango.webp"),
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Registro de Ciudadano',
                          style: TextStyle(
                            color: Color(0xFF1A1A2E),
                            fontSize: 16,
                            fontFamily: 'Plus Jakarta Sans',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Complete el formulario para continuar',
                          style: TextStyle(
                            color: Color(0xFFAAAABC),
                            fontSize: 12,
                            fontFamily: 'Plus Jakarta Sans',
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // banner promocional integrado como tarjeta interna
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'assets/images/banner_promocion.webp',
                  width: double.infinity,
                  height: 135, // altura del banner
                  fit: BoxFit.cover,
                ),
              ),
            ),
            // divisor antes de los campos para organizar visualmente
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 32),
              child: Divider(color: Colors.black12, height: 1),
            ),
            const SizedBox(height: 16),

            // campos del formulario
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 8),
              child: Form(
                key: formKey, // Asignamos la llave al formulario
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomTextField(
                      label: 'NOMBRE (S)',
                      hint: 'ej. MARÍA FERNANDA',
                      helper: 'Ingresa tu nombre (s)',
                      controller: nombreCtrl,
                      enabled: !isCargando,
                      textCapitalization: TextCapitalization.characters,
                      validator: Validadores.validarRequerido,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s]'),
                        ),
                        UpperCaseTextFormatter(),
                        SingleSpaceTextFormatter(),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: CustomTextField(
                            label: 'APELLIDO PATERNO',
                            hint: 'ej. GARCÍA',
                            helper: 'Ingresa tu apellido paterno',
                            controller: apellidoPaternoCtrl,
                            enabled: !isCargando,
                            textCapitalization: TextCapitalization.characters,
                            validator: Validadores.validarRequerido,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s]'),
                              ),
                              UpperCaseTextFormatter(),
                              SingleSpaceTextFormatter(),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: CustomTextField(
                            label: 'APELLIDO MATERNO',
                            hint: 'ej. LÓPEZ',
                            helper: 'Opcional si solo tienes un apellido',
                            controller: apellidoMaternoCtrl,
                            enabled: !isCargando,
                            textCapitalization: TextCapitalization.characters,
                            // Opcional: hay personas con un solo apellido.
                            // La base de datos ya lo guarda como NULL.
                            validator: null,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑüÜ\s]'),
                              ),
                              UpperCaseTextFormatter(),
                              SingleSpaceTextFormatter(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'TELÉFONO',
                      hint: 'ej. 6181234567',
                      helper: 'Ingresa tu número a 10 dígitos',
                      controller: telefonoCtrl,
                      enabled: !isCargando,
                      keyboardType: TextInputType.phone,
                      validator: Validadores.validarTelefono,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      label: 'NO. DE TRANSACCIÓN',
                      hint:
                          (transaccionFocus.hasFocus ||
                              transaccionCtrl.text.isNotEmpty)
                          ? 'ej. 000000'
                          : 'ej. ${DateTime.now().year}-000000',
                      helper: 'Ingresa los 6 dígitos de tu recibo',
                      controller: transaccionCtrl,
                      focusNode: transaccionFocus,
                      enabled: !isCargando,
                      keyboardType: TextInputType.number,
                      prefixText:
                          (transaccionFocus.hasFocus ||
                              transaccionCtrl.text.isNotEmpty)
                          ? '${DateTime.now().year}-'
                          : null,
                      validator: Validadores.validarTransaccion,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => onAceptar(),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(
                top: 8,
                left: 32,
                right: 32,
                bottom: 32,
              ),
              child: isCargando
                  ? const Center(child: CircularProgressIndicator())
                  : Row(
                      children: [
                        Expanded(
                          child: PrimaryButton(
                            text: 'Aceptar',
                            onPressed: onAceptar,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SecondaryButton(
                            text: 'Cancelar',
                            onPressed: onCancelar,
                          ),
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}