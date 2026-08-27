class ApiMunicipioService {
  // Simulamos la respuesta de la API. En el futuro, podmeos usar el paquete 'http' o 'dio'
  Future<Map<String, String>> validarTransaccion(String transaccion) async {
    await Future.delayed(const Duration(seconds: 2)); // Simulación de espera
    
    // Aquí se valida si fue pagada en octubre
    if (transaccion.isNotEmpty) {
      return {
        'direccion': 'C. Constitución #123, Zona Centro',
        'claveCatastral': '10-001-00-02-0001-082-170-00029-00-0000',
        'propietario': 'JUAN PEREZ GARCIA',
      };
    }
    throw Exception('Transacción inválida');
  }
}