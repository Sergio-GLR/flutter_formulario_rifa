import 'package:flutter/material.dart';
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
  
  final _nombreCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _transaccionCtrl = TextEditingController();

  final _apiService = ApiMunicipioService();
  final _supabaseService = SupabaseService();

  Map<String, String> _datosPredio = {};

  Future<void> _validarTransaccion() async {
    if (_nombreCtrl.text.isEmpty || _telefonoCtrl.text.isEmpty || _transaccionCtrl.text.isEmpty) {
      _mostrarSnackBar('Por favor, llena todos los campos');
      return;
    }

    setState(() => _currentState = FormStatus.validandoApi);

    try {
      final datos = await _apiService.validarTransaccion(_transaccionCtrl.text.trim());
      setState(() {
        _datosPredio = datos;
        _currentState = FormStatus.confirmacion;
      });
    } catch (e) {
      setState(() => _currentState = FormStatus.capturaInicial);
      _mostrarSnackBar('Transacción inválida. Verifica tus datos.');
    }
  }

  // Nuevo método para mostrar el modal del diagrama
  Future<void> _mostrarModalConfirmacion() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, 
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('¿Toda la información es correcta?'),
          content: const Text('Verifica que la dirección del predio corresponda a tu pago antes de generar el boleto.'),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancelar'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: const Text('Sí, registrar'),
              onPressed: () {
                Navigator.of(context).pop();
                _registrarBoleto();
              },
            ),
          ],
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
        telefono: _telefonoCtrl.text.trim(),
        clave: _datosPredio['claveCatastral']!,
        propietario: _datosPredio['propietario']!,
        direccion: _datosPredio['direccion']!,
      );

      if (response['success'] == true) {
        setState(() => _currentState = FormStatus.exito);
      } else {
        setState(() => _currentState = FormStatus.confirmacion);
        _mostrarSnackBar(response['message'], esError: true);
      }
    } catch (e) {
      setState(() => _currentState = FormStatus.confirmacion);
      _mostrarSnackBar('Error de conexión: $e', esError: true);
    }
  }

  void _mostrarSnackBar(String mensaje, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(mensaje),
        backgroundColor: esError ? Colors.red : null,
      ),
    );
  }

  void _reiniciarFormulario() {
    _nombreCtrl.clear();
    _telefonoCtrl.clear();
    _transaccionCtrl.clear();
    setState(() => _currentState = FormStatus.capturaInicial);
  }

  @override
  Widget build(BuildContext context) {
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
            constraints: const BoxConstraints(maxWidth: 500), // Responsivo web/móvil
            padding: const EdgeInsets.all(24.0),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: _currentState == FormStatus.exito 
                    ? _buildBoletoExito() 
                    : _buildFormulario(camposBloqueados),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBoletoExito() {
    return Column(
      children: [
        const Icon(Icons.check_circle, color: Colors.green, size: 80),
        const SizedBox(height: 16),
        const Text('¡Registro Exitoso!', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.green)),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            border: Border.all(color: Colors.blue.shade200, width: 2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              const Text('Tu Folio de Participación:', style: TextStyle(color: Colors.blueGrey)),
              Text(_transaccionCtrl.text.toUpperCase(), style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, letterSpacing: 2)),
            ],
          ),
        ),
        const SizedBox(height: 32),
        ElevatedButton(
          onPressed: _reiniciarFormulario,
          child: const Text('Registrar otro boleto'),
        ),
      ],
    );
  }

  Widget _buildFormulario(bool camposBloqueados) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Registro para la Rifa de Octubre', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 24),
        TextField(
          controller: _nombreCtrl,
          enabled: !camposBloqueados,
          decoration: const InputDecoration(labelText: 'Nombre de quien pagó', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _telefonoCtrl,
          enabled: !camposBloqueados,
          decoration: const InputDecoration(labelText: 'Teléfono', border: OutlineInputBorder()),
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _transaccionCtrl,
          enabled: !camposBloqueados,
          decoration: const InputDecoration(labelText: 'Número de Transacción', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 24),
        
        if (_currentState == FormStatus.confirmacion || _currentState == FormStatus.guardando) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.orange[50], borderRadius: BorderRadius.circular(8)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Por favor, confirma que esta es la dirección del predio:', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                const SizedBox(height: 8),
                Text(_datosPredio['direccion'] ?? '', style: const TextStyle(fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],

        if (_currentState == FormStatus.capturaInicial)
          ElevatedButton(
            onPressed: _validarTransaccion,
            child: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Validar Transacción', style: TextStyle(fontSize: 16))),
          )
        else if (_currentState == FormStatus.validandoApi || _currentState == FormStatus.guardando)
          const Center(child: CircularProgressIndicator())
        else if (_currentState == FormStatus.confirmacion)
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => setState(() => _currentState = FormStatus.capturaInicial),
                  child: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Corregir datos')),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _mostrarModalConfirmacion, // Ahora llama al modal primero
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Participar en la Rifa', style: TextStyle(color: Colors.white))),
                ),
              ),
            ],
          ),
      ],
    );
  }
}