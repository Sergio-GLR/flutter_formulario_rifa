import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_municipio_service.dart';
import '../services/supabase_service.dart';

enum FormStatus { capturaInicial, validandoApi, confirmacion, guardando, exito }

class FormularioScreen extends StatefulWidget {
  const FormularioScreen({super.key});

  @override
  State<FormularioScreen> createState() => _FormularioScreenState();
}

class _FormularioScreenState extends State<FormularioScreen> {
  FormStatus _currentState = FormStatus.capturaInicial;

  // Variables para controlar el estado visual de error de cada campo
  String? _errorNombre;
  String? _errorPaterno;
  String? _errorMaterno;
  String? _errorTelefono;
  String? _errorTransaccion;

  final _nombreCtrl = TextEditingController();
  final _apellidoPaternoCtrl = TextEditingController();
  final _apellidoMaternoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _transaccionCtrl = TextEditingController();

  final _apiService = ApiMunicipioService();
  final _supabaseService = SupabaseService();

  Map<String, String> _datosPredio = {};

  Future<void> _validarTransaccion() async {
    // Evaluamos qué campos están vacíos y actualizamos la UI
    setState(() {
      _errorNombre = _nombreCtrl.text.isEmpty ? 'Campo requerido' : null;
      _errorPaterno = _apellidoPaternoCtrl.text.isEmpty ? 'Requerido' : null;
      _errorMaterno = _apellidoMaternoCtrl.text.isEmpty ? 'Requerido' : null;
      _errorTelefono = _telefonoCtrl.text.isEmpty ? 'Requerido' : null;
      _errorTransaccion = _transaccionCtrl.text.isEmpty ? 'Requerido' : null;
    });

    // Si alguno tiene error, detenemos el proceso
    if (_errorNombre != null ||
        _errorPaterno != null ||
        _errorMaterno != null ||
        _errorTelefono != null ||
        _errorTransaccion != null) {
      _mostrarSnackBar('Por favor, completa los campos en rojo', esError: true);
      return;
    }

    setState(() => _currentState = FormStatus.validandoApi);

    try {
      final datos = await _apiService.validarTransaccion(
        _transaccionCtrl.text.trim(),
      );
      setState(() {
        _datosPredio = datos;
        _currentState = FormStatus.confirmacion;
      });
      _mostrarModalConfirmacion();
    } catch (e) {
      setState(() {
        _currentState = FormStatus.capturaInicial;
        _errorTransaccion = 'Ingresa un dato válido';
      });
    }
  }

  // cambie el AlertDialog por defecto por un Dialog personalizado que iguala al Figma
  Future<void> _mostrarModalConfirmacion() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          elevation: 0,
          child: Container(
            width: 593,
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
                Text(
                  'NO. DE TRANSACCIÓN: ${_transaccionCtrl.text}\nDIRECCIÓN: ${_datosPredio['direccion'] ?? 'No disponible'}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF4A4A4A),
                    fontSize: 20,
                    fontFamily: 'Plus Jakarta Sans',
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 32),
                Row(
                  children: [
                    Expanded(
                      child: _PrimaryButton(
                        text: 'Aceptar',
                        onPressed: () {
                          Navigator.of(context).pop();
                          _registrarBoleto();
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SecondaryButton(
                        text: 'Cancelar',
                        onPressed: () {
                          Navigator.of(context).pop();
                          setState(
                            () => _currentState = FormStatus.capturaInicial,
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _registrarBoleto() async {
    setState(() => _currentState = FormStatus.guardando);

    try {
      final response = await _supabaseService.registrarBoleto(
        transaccion: _transaccionCtrl.text.trim(),
        nombre: _nombreCtrl.text.trim(),
        apellidoPaterno: _apellidoPaternoCtrl.text.trim(),
        apellidoMaterno: _apellidoMaternoCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
        clave: _datosPredio['claveCatastral'] ?? '',
        propietario: _datosPredio['propietario'] ?? '',
        direccion: _datosPredio['direccion'] ?? '',
      );

      if (response['success'] == true) {
        setState(() => _currentState = FormStatus.exito);
      } else {
        setState(() => _currentState = FormStatus.capturaInicial);
        _mostrarSnackBar(response['message'], esError: true);
      }
    } catch (e) {
      setState(() => _currentState = FormStatus.capturaInicial);
      _mostrarSnackBar('Error de conexión: $e', esError: true);
    }
  }

  void _mostrarSnackBar(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? const Color(0xFFEB5757) : null,
      ),
    );
  }

  void _reiniciarFormulario() {
    _nombreCtrl.clear();
    _apellidoPaternoCtrl.clear();
    _apellidoMaternoCtrl.clear();
    _telefonoCtrl.clear();
    _transaccionCtrl.clear();
    setState(() {
      _currentState = FormStatus.capturaInicial;
      _errorNombre = null;
      _errorPaterno = null;
      _errorMaterno = null;
      _errorTelefono = null;
      _errorTransaccion = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isCargando =
        _currentState == FormStatus.validandoApi ||
        _currentState == FormStatus.guardando;

    return Scaffold(
      // csmbie el gradiente radial de fondo para que se vea como en figma
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0.60, 0.20),
            radius: 1.00,
            colors: [Color(0xFF858585), Color(0xFF54545D), Color(0xFF4A4A4A)],
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // destello suave de fondo
            Opacity(
              opacity: 0.03,
              child: Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.50, 0.50),
                    radius: 1.03,
                    colors: [Colors.white, Colors.black.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: _currentState == FormStatus.exito
                  ? _buildBoletoExito()
                  : _buildFormulario(isCargando),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoletoExito() {
    // implemente la tarjeta de exito con el diseño moradito claro
    return Container(
      width: 407,
      padding: const EdgeInsets.only(top: 40, bottom: 22, left: 32, right: 32),
      decoration: BoxDecoration(
        color: const Color(0xFFE0E0EC),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Colors.green, //color de la palomita
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
          const SizedBox(height: 32),
          // imagen del ticket (placeholder) para cambiarla despues
          // Container(
          //   width: 187,
          //   height: 107,
          //   decoration: const BoxDecoration(
          //     image: DecorationImage(
          //       image: NetworkImage("https://placehold.co/187x107"),
          //       fit: BoxFit.cover,
          //     ),
          //   ),
          // ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: _PrimaryButton(
                  text: 'Aceptar',
                  onPressed: _reiniciarFormulario,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _SecondaryButton(
                  text: 'Ver Resumen',
                  onPressed: () {
                    // aqui podemos agregar la lógica para ver el resumen despues
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFormulario(bool isCargando) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 512),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: const Color(0xFFF8F7FC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x7F000000),
              blurRadius: 80,
              offset: Offset(0, 32),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // borde superior degradado
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
            // header del card
            Container(
              padding: const EdgeInsets.only(
                top: 32,
                left: 32,
                right: 32,
                bottom: 24,
              ),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                ),
              ),
              child: Row(
                children: [
                  // aqui podemos cambiar el placeholder por el logo de Durango
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
            // contenido de los inputs
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CustomTextField(
                    label: 'NOMBRE (S)',
                    hint: 'ej. MARÍA FERNANDA',
                    helper: 'Ingresa tu nombre (s)',
                    controller: _nombreCtrl,
                    enabled: !isCargando,
                    errorText: _errorNombre,
                    onChanged: (value) => setState(() => _errorNombre = null),
                    textCapitalization:
                        TextCapitalization.characters, // Teclado en mayúsculas
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]'),
                      ), // Bloquea números y símbolos
                      _UpperCaseTextFormatter(), // Fuerza mayúsculas
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _CustomTextField(
                          label: 'APELLIDO PATERNO',
                          hint: 'ej. GARCÍA',
                          helper: 'Ingresa tu apellido paterno',
                          controller: _apellidoPaternoCtrl,
                          enabled: !isCargando,
                          errorText: _errorPaterno,
                          onChanged: (value) =>
                              setState(() => _errorPaterno = null),
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]'),
                            ),
                            _UpperCaseTextFormatter(),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: _CustomTextField(
                          label: 'APELLIDO MATERNO',
                          hint: 'ej. LÓPEZ',
                          helper: 'Ingresa tu apellido materno',
                          controller: _apellidoMaternoCtrl,
                          enabled: !isCargando,
                          errorText: _errorMaterno,
                          onChanged: (value) =>
                              setState(() => _errorMaterno = null),
                          textCapitalization: TextCapitalization.characters,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]'),
                            ),
                            _UpperCaseTextFormatter(),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _CustomTextField(
                    label: 'TELÉFONO',
                    hint: 'ej. 6181234567',
                    helper: 'Ingresa tu número de teléfono a 10 dígitos',
                    controller: _telefonoCtrl,
                    enabled: !isCargando,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(10),
                    ],
                    errorText: _errorTelefono,
                    onChanged: (value) => setState(() => _errorTelefono = null),
                  ),
                  const SizedBox(height: 16),

                  _CustomTextField(
                    label: 'NO. DE TRANSACCIÓN',
                    hint: 'ej. 2026-00000',
                    helper: 'Ingresa tu número de transacción',
                    controller: _transaccionCtrl,
                    enabled: !isCargando,
                    errorText: _errorTransaccion,
                    keyboardType: TextInputType.number,
                    inputFormatters: [_TransaccionFormatter()],
                    onChanged: (value) =>
                        setState(() => _errorTransaccion = null),
                  ),
                ],
              ),
            ),

            // Botones inferiores
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
                          child: _PrimaryButton(
                            text: 'Aceptar',
                            onPressed: _validarTransaccion,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SecondaryButton(
                            text: 'Cancelar',
                            onPressed: _reiniciarFormulario,
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

// aqui extraemos el textfield para no saturar de codigo el widget principal
class _CustomTextField extends StatelessWidget {
  final String label;
  final String hint;
  final String helper;
  final TextEditingController controller;
  final bool enabled;
  final TextInputType? keyboardType;
  final String? errorText;
  final List<TextInputFormatter>? inputFormatters; // <-- Nueva propiedad
  final ValueChanged<String>? onChanged; // <-- Nuevo propiedad
  final TextCapitalization textCapitalization; // <-- Nuevo propiedad

  const _CustomTextField({
    required this.label,
    required this.hint,
    required this.helper,
    required this.controller,
    this.enabled = true,
    this.keyboardType,
    this.errorText,
    this.inputFormatters, // <-- Se añade al constructor
    this.onChanged, // <-- Se añade al constructor
    this.textCapitalization = TextCapitalization.none, // <-- Valor por defecto
  });

  @override
  Widget build(BuildContext context) {
    final hasError = errorText != null;

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
        TextField(
          controller: controller,
          enabled: enabled,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          textCapitalization: textCapitalization,
          style: const TextStyle(
            color: Color(0xFF1A1A2E),
            fontSize: 14,
            fontFamily: 'Plus Jakarta Sans',
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(color: Color(0x7F1A1A2E)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            filled: true,
            fillColor: hasError
                ? const Color(0xFFEB5757).withValues(alpha: 0.08)
                : Colors.white,
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: hasError
                    ? const Color(0xFFEB5757)
                    : const Color(0xFFE0E0EC),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: hasError
                    ? const Color(0xFFEB5757)
                    : const Color(0xFFC4B5FD),
              ),
            ),
            disabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE0E0EC)),
            ),
            suffixIcon: hasError
                ? const Icon(
                    Icons.error_outline,
                    color: Color(0xFFEB5757),
                    size: 20,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          hasError ? errorText! : helper,
          style: TextStyle(
            color: hasError ? const Color(0xFFEB5757) : const Color(0xFFAAAABC),
            fontSize: 12,
            fontFamily: 'Plus Jakarta Sans',
          ),
        ),
      ],
    );
  }
}

// boton a ceptar con su gradiente
class _PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const _PrimaryButton({required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: ShapeDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFA0A0AC), Color(0xFF858585)],
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x667A5CFA),
              blurRadius: 20,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontFamily: 'Plus Jakarta Sans',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

// boton cancelar blanco con borde
class _SecondaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;

  const _SecondaryButton({required this.text, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onPressed,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: ShapeDecoration(
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: const BorderSide(color: Color(0xFFC4B5FD)),
            borderRadius: BorderRadius.circular(14),
          ),
          shadows: const [
            BoxShadow(
              color: Color(0x0F000000),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFFAAAABC),
              fontSize: 14,
              fontFamily: 'Plus Jakarta Sans',
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _TransaccionFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Eliminamos cualquier cosa que no sea un número
    String digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    // Limitamos a 9 dígitos máximo (4 del año + 5 del recibo)
    if (digits.length > 9) {
      digits = digits.substring(0, 9);
    }

    // Inyecta el guion automáticamente después del 4to dígito
    String formatted = digits;
    if (digits.length > 4) {
      formatted = '${digits.substring(0, 4)}-${digits.substring(4)}';
    }

    return TextEditingValue(
      text: formatted,
      // Mantienemos el cursor al final del texto mientras escribe
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _UpperCaseTextFormatter extends TextInputFormatter {
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
