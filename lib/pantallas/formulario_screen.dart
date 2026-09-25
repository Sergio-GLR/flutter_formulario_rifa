import 'package:flutter/material.dart';

import '../servicios/api_municipio_service.dart';
import '../servicios/supabase_service.dart';
import '../servicios/descargarBoleto.dart';

import '../componentes/terminos.dart';
import '../componentes/confirmacion.dart';
import '../componentes/avisoNoAceptado.dart';
import '../componentes/boletoExito.dart';
import '../componentes/tarjetaFormulario.dart';

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
      barrierColor: Colors.black12,
      builder: (BuildContext context) {
        return TerminosCondicionesDialog(
          onAceptar: () {
            setState(() {
              _terminosAceptados = true;
            });
            Navigator.of(context).pop();
          },
          onRechazar: () {
            Navigator.of(context).pop();
            _mostrarSnackBar(
              'Para participar en la rifa, es necesario aceptar los términos.',
              esError: true,
            );
          },
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
        return ConfirmacionDialog(
          transaccion: '${DateTime.now().year}-${_transaccionCtrl.text.trim()}',
          direccion: _datosPredio['direccion'] ?? 'No disponible',
          onConfirmar: () {
            Navigator.of(context).pop();
            _registrarBoleto();
          },
          onCancelar: () {
            Navigator.of(context).pop();
            setState(() => _currentState = FormStatus.capturaInicial);
          },
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
  void _descargarBoleto() {
    BoletoDescarga.descargarBoleto(
      key: _boletoKey,
      numeroTransaccion: _transaccionCtrl.text.trim(),
      onNotificar: (mensaje, {bool esError = false}) {
        _mostrarSnackBar(mensaje, esError: esError);
      },
    );
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
                                ? BoletoExito(
                                    boletoKey: _boletoKey,
                                    transaccion:
                                        '${DateTime.now().year}-${_transaccionCtrl.text.trim()}',
                                    // Solo une las partes con texto: sin apellido
                                    // materno no queda un espacio al final
                                    nombreUsuario: [
                                      _nombreCtrl.text.trim(),
                                      _apellidoPaternoCtrl.text.trim(),
                                      _apellidoMaternoCtrl.text.trim(),
                                    ].where((parte) => parte.isNotEmpty).join(' '),
                                    onDescargar: _descargarBoleto,
                                    onAceptar: _reiniciarFormulario,
                                  )
                                : (!_terminosAceptados
                                      ? AvisoNoAceptado(
                                          onRevisarTerminos:
                                              _mostrarTerminosYCondiciones,
                                        )
                                      : TarjetaFormulario(
                                          formKey: _formKey,
                                          nombreCtrl: _nombreCtrl,
                                          apellidoPaternoCtrl:
                                              _apellidoPaternoCtrl,
                                          apellidoMaternoCtrl:
                                              _apellidoMaternoCtrl,
                                          telefonoCtrl: _telefonoCtrl,
                                          transaccionCtrl: _transaccionCtrl,
                                          transaccionFocus: _transaccionFocus,
                                          isCargando: isCargando,
                                          onAceptar: _validarTransaccion,
                                          onCancelar: _reiniciarFormulario,
                                        )),
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
}

// el numero de transaccion esta asociada a la sisguiente direccion,
// deseas editarlo?
