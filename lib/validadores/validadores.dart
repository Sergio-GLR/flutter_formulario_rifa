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