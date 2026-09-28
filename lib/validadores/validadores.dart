class Validadores {
  //validar que un campo de texto no esté vacío o contenga solo espacios
  static String? validarRequerido(String? value, {String mensaje = 'Campo requerido'}) {
    if (value == null || value.trim().isEmpty){
      return mensaje;
    }
    return null;
  }

  //validar que el número telefónico cumpla con los 10 dígitos requeridos
  static String? validarTelefono(String? value){
    if(value == null || value.trim().isEmpty){
      return 'Campo requerido';
    }
    if (value.trim().length < 10) {
      return 'Debe contener 10 dígitos';
    }
    return null;
  }

  //convierte 'DD/MM/AAAA' en fecha; null si el formato o la fecha no existen (ej. 31/02)
  static DateTime? parsearFecha(String? value) {
    final m = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(value?.trim() ?? '');
    if (m == null) return null;
    final dia = int.parse(m[1]!);
    final mes = int.parse(m[2]!);
    final anio = int.parse(m[3]!);
    final fecha = DateTime(anio, mes, dia);
    // DateTime(2026, 2, 31) "se desborda" a marzo: así detectamos fechas inexistentes
    if (fecha.year != anio || fecha.month != mes || fecha.day != dia) return null;
    return fecha;
  }

  //validar la fecha de pago del recibo: formato DD/MM/AAAA, fecha real y no futura
  static String? validarFechaPago(String? value, {DateTime? hoy}) {
    if (value == null || value.trim().isEmpty) {
      return 'Campo requerido';
    }
    final fecha = parsearFecha(value);
    if (fecha == null) {
      return 'Fecha no válida (DD/MM/AAAA)';
    }
    final h = hoy ?? DateTime.now();
    if (fecha.isAfter(DateTime(h.year, h.month, h.day))) {
      return 'La fecha no puede ser futura';
    }
    return null;
  }

  //validar que el número de transacción contenga los 6 dígitos mínimos
  static String? validarTransaccion(String? value) {
    if (value == null || value.trim().isEmpty){
      return 'Campo requerido';
    }
    if (value.trim().length < 6){
      return 'Faltan dígitos';
    }
    return null;
  }
}