// La descarga del boleto usa APIs del navegador (dart:js_interop, package:web),
// que no existen en la VM de `flutter test`. Con este import condicional la
// app web usa la versión real y las pruebas usan un reemplazo sin navegador,
// así la pantalla completa se puede montar en las pruebas.
export 'descargarBoleto_stub.dart'
    if (dart.library.js_interop) 'descargarBoleto_web.dart';
