import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/formulario_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Cargamos las variables de entorno ANTES de inicializar Supabase
  await dotenv.load(fileName: ".env");

  // Inicializamos la conexión a tu base de datos
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    publishableKey: dotenv.env['SUPABASE_PUBLISHABLE_KEY']!,
  );

  runApp(const RifaPredialApp());
}

class RifaPredialApp extends StatelessWidget {
  const RifaPredialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rifa Predial - Octubretón',
      theme: ThemeData(primarySwatch: Colors.grey),
      home: const FormularioScreen(),
    );
  }
}
