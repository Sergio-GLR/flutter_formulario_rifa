import 'package:flutter/material.dart';

import 'pantallas/formulario_screen.dart';

// La app ya no carga .env ni se conecta a Supabase: todo pasa por el
// servicio interno (servicio_rifa), que es el único que guarda secretos.
void main() {
  runApp(const RifaPredialApp());
}

class RifaPredialApp extends StatelessWidget {
  const RifaPredialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false, // quite la etiqueta de debug
      title: 'Rifa Predial - Octubretón',
      theme: ThemeData(primarySwatch: Colors.grey),
      home: const FormularioScreen(),
    );
  }
}
