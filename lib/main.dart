import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'screens/formulario_screen.dart';

Future<void> main() async {
  // Aseguramos que los widgets de Flutter estén listos antes de inicializar plugins
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

// Creamos esta variable global para poder llamar a la base de datos
// fácilmente desde cualquier otro archivo de tu proyecto
final supabase = Supabase.instance.client;

class RifaPredialApp extends StatelessWidget {
  const RifaPredialApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rifa Predial - Octubre',
      theme: ThemeData(
        primarySwatch:
            Colors.grey, // Puedes ajustarlo a los colores de la institución
      ),
      home: const FormularioScreen(),
    );
  }
}
