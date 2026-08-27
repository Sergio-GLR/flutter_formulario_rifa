import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  final _supabase = Supabase.instance.client;

  Future<Map<String, dynamic>> registrarBoleto({
    required String transaccion,
    required String nombre,
    required String telefono,
    required String clave,
    required String propietario,
    required String direccion,
  }) async {
    final response = await _supabase.rpc(
      'registrar_boleto_rifa',
      params: {
        'p_numero_transaccion': transaccion,
        'p_nombre_pagador': nombre,
        'p_telefono_pagador': telefono,
        'p_clave_catastral': clave,
        'p_propietario_registrado': propietario,
        'p_direccion_predio': direccion,
      },
    );
    return response;
  }
}