import 'dart:convert';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  static const String _supabaseUrlEnv = String.fromEnvironment('SUPABASE_URL');
  static const String _supabaseAnonKeyEnv = String.fromEnvironment('SUPABASE_ANON_KEY');

  static String get supabaseUrl {
    if (_supabaseUrlEnv.isNotEmpty) return _supabaseUrlEnv;
    return dotenv.env['SUPABASE_URL'] ?? '';
  }

  static String get supabaseAnonKey {
    if (_supabaseAnonKeyEnv.isNotEmpty) return _supabaseAnonKeyEnv;
    return dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  }

  static void validate() {
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      throw StateError(
        'Faltan SUPABASE_URL y/o SUPABASE_ANON_KEY. '
        'Ejecuta con --dart-define-from-file=config/dev.json o provee variables de entorno.',
      );
    }
  }

  /// Verifica si el JWT emitido para Firebase contiene el custom claim "role: authenticated"
  /// requerido por las políticas RLS de Supabase.
  static bool hasAuthenticatedRole(String idToken) {
    try {
      final parts = idToken.split('.');
      if (parts.length != 3) return false;
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      ) as Map<String, dynamic>;
      return payload['role'] == 'authenticated';
    } catch (_) {
      return false;
    }
  }
}
