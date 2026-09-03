import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/api_municipio_service.dart';
import '../services/supabase_service.dart';

// import 'package:google_fonts/google_fonts.dart';

enum FormStatus { capturaInicial, validandoApi, confirmacion, guardando, exito }

class FormularioScreen extends StatefulWidget {
  const FormularioScreen({super.key});

  @override
  State<FormularioScreen> createState() => _FormularioScreenState();
}

class _FormularioScreenState extends State<FormularioScreen> {
  FormStatus _currentState = FormStatus.capturaInicial;

  // variables para controlar el estado visual de error de cada campo
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

  late FocusNode _transaccionFocus;

  @override
  void initState() {
    super.initState();
    _transaccionFocus = FocusNode();
    _transaccionFocus.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _transaccionFocus.dispose();
    _nombreCtrl.dispose();
    _apellidoPaternoCtrl.dispose();
    _apellidoMaternoCtrl.dispose();
    _telefonoCtrl.dispose();
    _transaccionCtrl.dispose();
    super.dispose();
  }

  final _apiService = ApiMunicipioService();
  final _supabaseService = SupabaseService();

  Map<String, String> _datosPredio = {};

  Future<void> _validarTransaccion() async {
    // evaluamos que campos están vacios y actualizamos la UI
    setState(() {
      _errorNombre = _nombreCtrl.text.isEmpty ? 'Campo requerido' : null;
      _errorPaterno = _apellidoPaternoCtrl.text.isEmpty
          ? 'Campo Requerido'
          : null;
      _errorMaterno = _apellidoMaternoCtrl.text.isEmpty
          ? 'Campo Requerido'
          : null;

      // Hacemos una validacion para exigir la longitud completa
      _errorTelefono = _telefonoCtrl.text.length < 10
          ? 'Debe contener 10 dígitos'
          : null;
      _errorTransaccion = _transaccionCtrl.text.length < 5
          ? 'Faltan dígitos'
          : null;
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
      final transaccionCompleta =
          '${DateTime.now().year}-${_transaccionCtrl.text.trim()}';
      final datos = await _apiService.validarTransaccion(transaccionCompleta);
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

  Future<void> _mostrarModalConfirmacion() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
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
                  'NO. DE TRANSACCIÓN: ${DateTime.now().year}-${_transaccionCtrl.text}\nDIRECCIÓN: ${_datosPredio['direccion'] ?? 'No disponible'}',
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
      final transaccionCompleta =
          '${DateTime.now().year}-${_transaccionCtrl.text.trim()}';

      final response = await _supabaseService.registrarBoleto(
        transaccion: transaccionCompleta,
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

        //cambio para poder navegar por fuera del formulario (se nota mas en pc)
        child: Stack(
          children: [
            Positioned.fill(
              child: Opacity(
                opacity: 0.03,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.50, 0.50),
                      radius: 1.03,
                      colors: [Colors.white, Colors.transparent],
                    ),
                  ),
                ),
              ),
            ),
            // con LayoutBuilder el scroll ocupeatoda la pantalla y centra el contenido
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: _currentState == FormStatus.exito
                              ? _buildBoletoExito()
                              : _buildFormulario(isCargando),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoletoExito() {
    return Container(
      width: 407,
      padding: const EdgeInsets.only(top: 40, bottom: 22, left: 32, right: 32),
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

          Boleto(
            transaccion:
                '${DateTime.now().year}-${_transaccionCtrl.text.trim()}',
            nombreUsuario:
                '${_nombreCtrl.text} ${_apellidoPaternoCtrl.text} ${_apellidoMaternoCtrl.text}',
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
                child: _PrimaryButton(
                  text: 'Aceptar',
                  onPressed: _reiniciarFormulario,
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
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]'),
                      ),
                      _UpperCaseTextFormatter(),
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
                    hint:
                        (_transaccionFocus.hasFocus ||
                            _transaccionCtrl.text.isNotEmpty)
                        ? 'ej. 00000'
                        : 'ej. ${DateTime.now().year}-00000',
                    helper: 'Ingresa los 5 dígitos de tu recibo',
                    controller: _transaccionCtrl,
                    focusNode: _transaccionFocus,
                    enabled: !isCargando,
                    errorText: _errorTransaccion,
                    keyboardType: TextInputType.number,
                    prefixText:
                        (_transaccionFocus.hasFocus ||
                            _transaccionCtrl.text.isNotEmpty)
                        ? '${DateTime.now().year}-'
                        : null,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(5),
                    ],
                    onChanged: (value) =>
                        setState(() => _errorTransaccion = null),
                  ),
                ],
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

class _CustomTextField extends StatelessWidget {
  final String label;
  final String hint;
  final String helper;
  final TextEditingController controller;
  final bool enabled;
  final TextInputType? keyboardType;
  final String? errorText;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;
  final TextCapitalization textCapitalization;
  final FocusNode? focusNode;
  final String? prefixText;

  const _CustomTextField({
    required this.label,
    required this.hint,
    required this.helper,
    required this.controller,
    this.enabled = true,
    this.keyboardType,
    this.errorText,
    this.inputFormatters,
    this.onChanged,
    this.textCapitalization = TextCapitalization.none,
    this.focusNode,
    this.prefixText,
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
          focusNode: focusNode,
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
            prefixText: prefixText,
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

// BOLETO
class Boleto extends StatelessWidget {
  final String transaccion;
  final String nombreUsuario;

  const Boleto({
    super.key,
    required this.transaccion,
    required this.nombreUsuario,
  });

  @override
  Widget build(BuildContext context) {
    const double relacionAspectoImagen = 2.5;

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: AspectRatio(
        aspectRatio: relacionAspectoImagen,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              Image.asset(
                'assets/images/boleto.png',
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.cover,
              ),

              Positioned(
                bottom: 12,
                right: 15,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        Text(
                          nombreUsuario.toUpperCase(),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 4.0
                              ..strokeCap = StrokeCap.round
                              ..strokeJoin = StrokeJoin.round
                              ..color = Color(0xFF001F54),
                          ),
                        ),
                        Text(
                          nombreUsuario.toUpperCase(),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                            fontStyle: FontStyle.italic,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                offset: Offset(2, 2),
                                blurRadius: 3,
                                color: Colors.black38,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 4),

                    const Text(
                      'NO. DE BOLETO:',
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            color: Colors.black87,
                            blurRadius: 4,
                            offset: Offset(1, 1),
                          ),
                        ],
                      ),
                    ),

                    Stack(
                      alignment: Alignment.centerRight,
                      children: [
                        Text(
                          transaccion,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            foreground: Paint()
                              ..style = PaintingStyle.stroke
                              ..strokeWidth = 3.0
                              ..strokeCap = StrokeCap.round
                              ..strokeJoin = StrokeJoin.round
                              ..color = Colors.white,
                          ),
                        ),
                        Text(
                          transaccion,
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                            color: Color.fromARGB(255, 168, 0, 70),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
