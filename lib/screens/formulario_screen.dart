import 'package:flutter/material.dart';

import '../main.dart'; // Para acceder a tu variable global 'supabase'

// Definimos los 5 estados de nuestro diagrama de flujo
enum FormStatus { capturaInicial, validandoApi, confirmacion, guardando, exito }

class FormularioScreen extends StatefulWidget {
  const FormularioScreen({super.key});

  @override
  State<FormularioScreen> createState() => _FormularioScreenState();
}

class _FormularioScreenState extends State<FormularioScreen> {
  // Estado actual del formulario
  FormStatus _currentState = FormStatus.capturaInicial;
  final _formKey = GlobalKey<FormState>();

  // Controladores de los campos
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _transaccionCtrl = TextEditingController();

  // Variables para guardar los datos de la API
  String _direccionObtenida = '';
  String _claveCatastralObtenida = '';
  String _propietarioObtenido = '';

  // --- MÉTODOS LÓGICOS ---

  Future<void> _validarTransaccion() async {
    // Validamos que no haya campos vacíos
    if (_nombreCtrl.text.isEmpty ||
        _telefonoCtrl.text.isEmpty ||
        _transaccionCtrl.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, llena todos los campos')),
      );
      return;
    }

    setState(() => _currentState = FormStatus.validandoApi);

    try {
      // AQUÍ IRÁ TU LLAMADA A LA API REST INSTITUCIONAL
      // Simulamos una espera de 2 segundos...
      await Future.delayed(const Duration(seconds: 2));

      // Simulamos la respuesta exitosa de la API
      setState(() {
        _direccionObtenida =
            'C. Constitución #123, Zona Centro'; // Dato simulado
        _claveCatastralObtenida =
            '10-001-00-02-0001-082-170-00029-00-0000'; // Dato simulado
        _propietarioObtenido = 'JUAN PEREZ GARCIA'; // Dato simulado

        _currentState = FormStatus.confirmacion;
      });
    } catch (e) {
      setState(() => _currentState = FormStatus.capturaInicial);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Error al validar la transacción')),
      );
    }
  }

  Future<void> _registrarBoleto() async {
    setState(() => _currentState = FormStatus.guardando);

    try {
      // Llamada a nuestro RPC en Supabase
      final response = await supabase.rpc(
        'registrar_boleto_rifa',
        params: {
          'p_numero_transaccion': _transaccionCtrl.text.trim(),
          'p_nombre_pagador': _nombreCtrl.text.trim(),
          'p_telefono_pagador': _telefonoCtrl.text.trim(),
          'p_clave_catastral': _claveCatastralObtenida,
          'p_propietario_registrado': _propietarioObtenido,
          'p_direccion_predio': _direccionObtenida,
        },
      );

      if (response['success'] == true) {
        setState(() => _currentState = FormStatus.exito);
      } else {
        // Mostramos el error (ej. "Esta transacción ya existe")
        setState(() => _currentState = FormStatus.confirmacion);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(response['message']),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      setState(() => _currentState = FormStatus.confirmacion);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error de conexión: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _reiniciarFormulario() {
    _nombreCtrl.clear();
    _telefonoCtrl.clear();
    _transaccionCtrl.clear();
    setState(() => _currentState = FormStatus.capturaInicial);
  }

  // --- CONSTRUCCIÓN DE LA UI ---

  @override
  Widget build(BuildContext context) {
    // Definimos si los campos deben estar bloqueados (solo lectura)
    final bool camposBloqueados = _currentState != FormStatus.capturaInicial;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Unidad Administrativa Municipal - Sorteo Predial'),
        centerTitle: true,
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Container(
            constraints: const BoxConstraints(
              maxWidth: 500,
            ), // Limita el ancho en web
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Registro para la Rifa de Octubre',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),

                    // --- ESTADO: ÉXITO (MUESTRA EL BOLETO) ---
                    if (_currentState == FormStatus.exito) ...[
                      const Icon(
                        Icons.check_circle,
                        color: Colors.green,
                        size: 80,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '¡Registro Exitoso!',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.blue[50],
                          border: Border.all(
                            color: Colors.blue.shade200,
                            style: BorderStyle.solid,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          children: [
                            const Text(
                              'Tu Folio de Participación:',
                              style: TextStyle(color: Colors.blueGrey),
                            ),
                            Text(
                              _transaccionCtrl.text.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton(
                        onPressed: _reiniciarFormulario,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                        child: const Text('Registrar otro boleto'),
                      ),
                    ]
                    // --- ESTADOS: CAPTURA, CARGA Y CONFIRMACIÓN ---
                    else ...[
                      TextField(
                        controller: _nombreCtrl,
                        enabled: !camposBloqueados,
                        decoration: const InputDecoration(
                          labelText: 'Nombre de quien pagó',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _telefonoCtrl,
                        enabled: !camposBloqueados,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _transaccionCtrl,
                        enabled: !camposBloqueados,
                        decoration: const InputDecoration(
                          labelText: 'Número de Transacción',
                          border: OutlineInputBorder(),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // --- CAMPO DE CONFIRMACIÓN (SOLO LECTURA) ---
                      if (_currentState == FormStatus.confirmacion ||
                          _currentState == FormStatus.guardando) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.orange[50],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Por favor, confirma que esta es la dirección del predio:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _direccionObtenida,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),
                      ],

                      // --- BOTONES DINÁMICOS SEGÚN EL ESTADO ---
                      if (_currentState == FormStatus.capturaInicial)
                        ElevatedButton(
                          onPressed: _validarTransaccion,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: const Text(
                            'Validar Transacción',
                            style: TextStyle(fontSize: 16),
                          ),
                        )
                      else if (_currentState == FormStatus.validandoApi ||
                          _currentState == FormStatus.guardando)
                        const Center(child: CircularProgressIndicator())
                      else if (_currentState == FormStatus.confirmacion)
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => setState(
                                  () =>
                                      _currentState = FormStatus.capturaInicial,
                                ),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                ),
                                child: const Text('Corregir datos'),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: ElevatedButton(
                                onPressed: _registrarBoleto,
                                style: ElevatedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 16,
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                                child: const Text(
                                  'Participar en la Rifa',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
