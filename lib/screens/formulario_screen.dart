import 'dart:ui' as ui;
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
  bool _terminosAceptados = false;

  // variables para controlar el estado visual de error de cada campo
  final _formKey = GlobalKey<FormState>();

  final _nombreCtrl = TextEditingController();
  final _apellidoPaternoCtrl = TextEditingController();
  final _apellidoMaternoCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _transaccionCtrl = TextEditingController();

  late FocusNode _transaccionFocus;

  // llave global para capturar el widget del boleto (impresion/descarga del boleto)
  final GlobalKey _boletoKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _transaccionFocus = FocusNode();
    _transaccionFocus.addListener(() {
      setState(() {});
    });

    // Despliega el modal de terminos y condiciones justo al terminar de dibujar la pantalla
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _mostrarTerminosYCondiciones();
      // Precarga la imagen en caché de forma silenciosa.
      precacheImage(const AssetImage('assets/images/boleto.png'), context);
    });
  }

  void _mostrarTerminosYCondiciones() {
    showDialog<void>(
      context: context,
      barrierDismissible:
          false, // Evita que lo cierren tocando fuera del recuadro
      barrierColor: Colors.black87,
      builder: (BuildContext context) {
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
                      child: _SecondaryButton(
                        text: 'No Acepto',
                        onPressed: () {
                          // Al no aceptar, cerramos el modal pero el estado sigue en false
                          Navigator.of(context).pop();
                          _mostrarSnackBar(
                            'Para participar en la rifa, es necesario aceptar los términos.',
                            esError: true,
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _PrimaryButton(
                        text: 'Aceptar',
                        onPressed: () {
                          // Cambiamos el estado a true y cerramos el modal
                          setState(() {
                            _terminosAceptados = true;
                          });
                          Navigator.of(context).pop();
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
    // Si el formulario ya está procesando una solicitud, ignoramos nuevos toques
    if (_currentState == FormStatus.validandoApi ||
        _currentState == FormStatus.guardando) {
      return;
    }

    if (!_formKey.currentState!.validate()) {
      _mostrarSnackBar(
        'Por favor, completa los campos correctamente',
        esError: true,
      );
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
      });

      final mensajeError = e.toString().replaceAll('Exception: ', '');
      _mostrarSnackBar(mensajeError, esError: true);
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
          // El widget Focus con autofocus captura los eventos del teclado globalmente
          child: Focus(
            autofocus: true,
            onKeyEvent: (FocusNode node, KeyEvent event) {
              // Si el usuario presiona la tecla Enter, confirmamos el modal
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.enter) {
                Navigator.of(context).pop();
                _registrarBoleto();
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
                          text: '${DateTime.now().year}-${_transaccionCtrl.text}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        TextSpan(
                          text: ' está asociado a la siguiente dirección:\n\n${_datosPredio['direccion'] ?? 'No disponible'}\n\n¿Es correcta la dirección?',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    children: [
                      // Botón principal restaurado a la izquierda
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
                      // Botón secundario restaurado a la derecha
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
          ),
        );
      },
    );
  }

  Future<void> _registrarBoleto() async {
    // Previene múltiples registros si el usuario hace doble clic rápido en el modal
    if (_currentState == FormStatus.guardando) return;

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

        // La imagen ya está en caché, solo esperamos a que el frame se dibuje
        WidgetsBinding.instance.addPostFrameCallback((_) {
          // Un retraso minúsculo de 150ms asegura que el RepaintBoundary esté listo
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) _descargarBoleto();
          });
        });
      } else {
        setState(() => _currentState = FormStatus.capturaInicial);
        _mostrarSnackBar(response['message'], esError: true);
      }
    } catch (e) {
      setState(() => _currentState = FormStatus.capturaInicial);
      _mostrarSnackBar('Error de conexión: $e', esError: true);
    }
  }

  // logica para capturar y descargar usando package:web
  Future<void> _descargarBoleto() async {
    _mostrarSnackBar('Generando tu boleto, por favor espera...');

    try {
      RenderRepaintBoundary boundary =
          _boletoKey.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(
        format: ui.ImageByteFormat.png,
      );
      Uint8List pngBytes = byteData!.buffer.asUint8List();

      final blob = web.Blob([pngBytes.toJS].toJS);
      final url = web.URL.createObjectURL(blob);

      web.HTMLAnchorElement()
        ..href = url
        ..download = 'boleto_rifa_octubre_${_transaccionCtrl.text}.png'
        ..click();

      web.URL.revokeObjectURL(url);
    } catch (e) {
      _mostrarSnackBar(
        'No se pudo descargar el boleto, intenta tomar una captura de pantalla.',
        esError: true,
      );
    }
  }

  void _mostrarSnackBar(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError
            ? const Color(0xFFEB5757)
            : const Color(0xFF4A4A4A),
      ),
    );
  }

  void _reiniciarFormulario() {
    // 1. Vaciamos el texto de todos los campos
    _nombreCtrl.clear();
    _apellidoPaternoCtrl.clear();
    _apellidoMaternoCtrl.clear();
    _telefonoCtrl.clear();
    _transaccionCtrl.clear();

    setState(() {
      // 2. Resetea las validaciones visuales (quita los mensajes de error en rojo)
      _formKey.currentState?.reset();

      // 3. Devolvemos la vista al estado original
      _currentState = FormStatus.capturaInicial;
    });
  }

  @override
  Widget build(BuildContext context) {
    final bool isCargando =
        _currentState == FormStatus.validandoApi ||
        _currentState == FormStatus.guardando;

    return Scaffold(
      body: AbsorbPointer(
        absorbing: isCargando, // Bloquea la interacción si está cargando
        child: Container(
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
              // con LayoutBuilder el scroll ocupa toda la pantalla y centra el contenido
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
                                : (!_terminosAceptados
                                      ? _buildAvisoNoAceptado() // Si no ha aceptado, bloqueamos
                                      : _buildFormulario(
                                          isCargando,
                                        )), // Formulario normal
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
      ),
    );
  }

  Widget _buildBoletoExito() {
    return Container(
      width: MediaQuery.of(context).size.width * 0.9,
      constraints: const BoxConstraints(maxWidth: 407),
      padding: EdgeInsets.only(
        top: 40,
        bottom: 22,
        left: MediaQuery.of(context).size.width < 450 ? 16 : 32,
        right: MediaQuery.of(context).size.width < 450 ? 16 : 32,
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
            key: _boletoKey,
            child: Boleto(
              transaccion:
                  '${DateTime.now().year}-${_transaccionCtrl.text.trim()}',
              nombreUsuario:
                  '${_nombreCtrl.text.trim()} ${_apellidoPaternoCtrl.text.trim()} ${_apellidoMaternoCtrl.text.trim()}',
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
                child: _SecondaryButton(
                  text: 'Descargar',
                  onPressed: _descargarBoleto,
                ),
              ),
              const SizedBox(width: 12),
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

  Widget _buildAvisoNoAceptado() {
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
              child: _PrimaryButton(
                text: 'Revisar Términos',
                onPressed: _mostrarTerminosYCondiciones,
              ),
            ),
          ],
        ),
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
              child: Form(
                key: _formKey, // Asignamos la llave al formulario
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _CustomTextField(
                      label: 'NOMBRE (S)',
                      hint: 'ej. MARÍA FERNANDA',
                      helper: 'Ingresa tu nombre (s)',
                      controller: _nombreCtrl,
                      enabled: !isCargando,
                      textCapitalization: TextCapitalization.characters,
                      validator: (value) =>
                          value == null || value.trim().isEmpty
                          ? 'Campo requerido'
                          : null,
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]'),
                        ),
                        _UpperCaseTextFormatter(),
                        _SingleSpaceTextFormatter(),
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
                            textCapitalization: TextCapitalization.characters,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Campo requerido'
                                : null,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]'),
                              ),
                              _UpperCaseTextFormatter(),
                              _SingleSpaceTextFormatter(),
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
                            textCapitalization: TextCapitalization.characters,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                ? 'Campo requerido'
                                : null,
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-ZáéíóúÁÉÍÓÚñÑ\s]'),
                              ),
                              _UpperCaseTextFormatter(),
                              _SingleSpaceTextFormatter(),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _CustomTextField(
                      label: 'TELÉFONO',
                      hint: 'ej. 6181234567',
                      helper: 'Ingresa tu número a 10 dígitos',
                      controller: _telefonoCtrl,
                      enabled: !isCargando,
                      keyboardType: TextInputType.phone,
                      validator: (value) =>
                          value == null || value.trim().length < 10
                          ? 'Debe contener 10 dígitos'
                          : null,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _CustomTextField(
                      label: 'NO. DE TRANSACCIÓN',
                      hint:
                          (_transaccionFocus.hasFocus ||
                              _transaccionCtrl.text.isNotEmpty)
                          ? 'ej. 000000'
                          : 'ej. ${DateTime.now().year}-000000',
                      helper: 'Ingresa los 6 dígitos de tu recibo',
                      controller: _transaccionCtrl,
                      focusNode: _transaccionFocus,
                      enabled: !isCargando,
                      keyboardType: TextInputType.number,
                      prefixText:
                          (_transaccionFocus.hasFocus ||
                              _transaccionCtrl.text.isNotEmpty)
                          ? '${DateTime.now().year}-'
                          : null,
                      validator: (value) =>
                          value == null || value.trim().length < 6
                          ? 'Faltan dígitos'
                          : null,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _validarTransaccion(),
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
  final List<TextInputFormatter>? inputFormatters;
  final TextCapitalization textCapitalization;
  final FocusNode? focusNode;
  final String? prefixText;
  final String? Function(String?)? validator; // propiedad para validar
  final ValueChanged<String>?
  onFieldSubmitted; // variable para manejar el evento de envío del campo
  final TextInputAction? textInputAction; // accion del teclado

  const _CustomTextField({
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
                              ..color = const Color(0xFF001F54),
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

class _SingleSpaceTextFormatter extends TextInputFormatter {
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

// el numero de transaccion esta asociada a la sisguiente direccion,
// deseas editarlo?
