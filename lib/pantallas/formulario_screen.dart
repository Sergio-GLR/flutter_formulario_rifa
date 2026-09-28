import 'package:flutter/material.dart';

import '../servicios/servicio_rifa.dart';
import '../servicios/descargarBoleto.dart';
import '../validadores/validadores.dart';

import '../componentes/terminos.dart';
import '../componentes/confirmacion.dart';
import '../componentes/avisoNoAceptado.dart';
import '../componentes/boletoExito.dart';
import '../componentes/tarjetaFormulario.dart';

enum FormStatus { capturaInicial, validandoApi, confirmacion, guardando, exito }

class FormularioScreen extends StatefulWidget {
  /// Cliente del servicio interno. Las pruebas pasan uno simulado; la app usa
  /// el real.
  final ServicioRifa? servicio;

  const FormularioScreen({super.key, this.servicio});

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
  final _fechaPagoCtrl = TextEditingController();

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
    _fechaPagoCtrl.dispose();
    super.dispose();
  }

  // Toda la comunicación pasa por el servicio interno: la app ya no conoce
  // el token/salt del SRM ni ninguna clave de Supabase.
  late final ServicioRifa _servicio = widget.servicio ?? ServicioRifa();

  // Datos que el ciudadano confirmó en el modal; el registro usa exactamente estos
  String _txcaValidada = '';
  DateTime? _fechaValidada;
  String _direccion = '';

  // Boleto tal como lo registró el servicio: es lo que se muestra y se descarga
  BoletoRegistrado? _boleto;

  String _mensajeDe(Object e) =>
      e is ErrorServicio ? e.mensaje : ServicioRifa.msgInesperado;

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
      // Ya pasó el validador del formulario, así que la fecha es válida
      final fechaPago = Validadores.parsearFecha(_fechaPagoCtrl.text)!;
      // El año del folio es el del pago, no el del reloj del equipo: quien
      // pagó en diciembre y se registra en enero conserva el año de su recibo.
      final transaccionCompleta =
          '${fechaPago.year}-${_transaccionCtrl.text.trim()}';
      final direccion = await _servicio.validar(
        transaccion: transaccionCompleta,
        fechaPago: fechaPago,
      );
      if (!mounted) return;

      setState(() {
        _txcaValidada = transaccionCompleta;
        _fechaValidada = fechaPago;
        _direccion = direccion;
        _currentState = FormStatus.confirmacion;
      });
      _mostrarModalConfirmacion();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _currentState = FormStatus.capturaInicial;
      });
      _mostrarSnackBar(_mensajeDe(e), esError: true);
    }
  }

  Future<void> _mostrarModalConfirmacion() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black54,
      builder: (BuildContext context) {
        return ConfirmacionDialog(
          transaccion: _txcaValidada,
          direccion: _direccion,
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
      // El servicio vuelve a verificar con el SRM y toma de ahí los datos del
      // predio; la app ya no los envía.
      final boleto = await _servicio.registrar(
        transaccion: _txcaValidada,
        fechaPago: _fechaValidada!,
        nombre: _nombreCtrl.text.trim(),
        apellidoPaterno: _apellidoPaternoCtrl.text.trim(),
        apellidoMaterno: _apellidoMaternoCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
      );
      if (!mounted) return;

      // Sin descarga automática: en los módulos del municipio el equipo es
      // compartido y el PNG (nombre + folio) quedaría para la siguiente
      // persona. El ciudadano ve su boleto en pantalla y puede usar el
      // botón "Descargar" si lo quiere.
      setState(() {
        _boleto = boleto;
        _currentState = FormStatus.exito;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _currentState = FormStatus.capturaInicial);
      // Mensaje amigable del servicio (nunca el error técnico)
      _mostrarSnackBar(_mensajeDe(e), esError: true);
    }
  }

  // logica para capturar y descargar usando package:web
  void _descargarBoleto() {
    BoletoDescarga.descargarBoleto(
      key: _boletoKey,
      numeroTransaccion: _boleto?.txca ?? _txcaValidada,
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
    _fechaPagoCtrl.clear();
    _txcaValidada = '';
    _fechaValidada = null;
    _direccion = '';
    _boleto = null;

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
                            child: _currentState == FormStatus.exito &&
                                    _boleto != null
                                ? BoletoExito(
                                    boletoKey: _boletoKey,
                                    // Folio y nombre tal como quedaron registrados
                                    // en el servicio, no recalculados aquí
                                    transaccion: _boleto!.txca,
                                    nombreUsuario: _boleto!.nombre,
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
                                          fechaPagoCtrl: _fechaPagoCtrl,
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
