import 'dart:math';

class ApiMunicipioService {
  // Lista con diferentes respuestas simuladas
  final List<Map<String, String>> _respuestasSimuladas = [
    {
      'direccion': 'C. Constitución #123, Zona Centro',
      'claveCatastral': '10-001-00-02-0001-082-170-00029-00-0000',
      'propietario': 'JUAN PEREZ GARCIA',
    },
    {
      'direccion': 'Av. 20 de Noviembre #456, Barrio del Calvario',
      'claveCatastral': '10-002-00-05-0012-045-120-00015-00-0000',
      'propietario': 'MARIA LOPEZ FERNANDEZ',
    },
    {
      'direccion': 'Blvd. Francisco Villa #789, Fracc. Las Américas',
      'claveCatastral': '10-003-00-08-0034-099-210-00088-00-0000',
      'propietario': 'CARLOS RODRIGUEZ MARTINEZ',
    },
    {
      'direccion': 'Calle Victoria #101, Barrio de Tierra Blanca',
      'claveCatastral': '10-004-00-01-0005-012-050-00003-00-0000',
      'propietario': 'ANA RUIZ GOMEZ',
    },
    {
      'direccion': 'C. 5 de Febrero #222, Zona Centro',
      'claveCatastral': '10-001-00-03-0010-085-180-00045-00-0000',
      'propietario': 'LUIS HERNANDEZ FLORES',
    },
    {
      'direccion': 'Blvd. Felipe Pescador #1400, Col. Esperanza',
      'claveCatastral': '10-005-00-12-0045-102-230-00112-00-0000',
      'propietario': 'SOFIA RAMIREZ SOTO',
    },
    {
      'direccion': 'C. Zarco #312, Barrio de Analco',
      'claveCatastral': '10-002-00-04-0015-055-130-00022-00-0000',
      'propietario': 'PEDRO CHAVEZ LUNA',
    },
    {
      'direccion': 'Av. Fidel Velázquez #334, Fracc. Fidel Velázquez',
      'claveCatastral': '10-007-00-09-0060-120-250-00150-00-0000',
      'propietario': 'LAURA SALAZAR NAVARRO',
    },
    {
      'direccion': 'C. Negrete #505, Zona Centro',
      'claveCatastral': '10-001-00-02-0008-081-160-00033-00-0000',
      'propietario': 'ROBERTO CASTRO MORALES',
    },
  ];

  // Simulamos la respuesta de la API. En el futuro, podmeos usar el paquete 'http' o 'dio'
  Future<Map<String, String>> validarTransaccion(String transaccion) async {
    await Future.delayed(
      const Duration(seconds: 2),
    ); // Simulación de espera de red

    if (transaccion.isNotEmpty) {
      // Generamos un índice aleatorio basado en el tamaño de la lista
      final random = Random();
      final index = random.nextInt(_respuestasSimuladas.length);

      // Retornamos el mapa correspondiente al índice elegido
      return _respuestasSimuladas[index];
    }

    throw Exception('Transacción inválida');
  }
}
