import 'package:firebase_auth/firebase_auth.dart';
import '../errors/app_exception.dart';
import '../../models/user_profile.dart';
import 'supabase_service.dart';

class AuthService {
  static final FirebaseAuth _auth = FirebaseAuth.instance;

  static User? get currentUser => _auth.currentUser;
  static Stream<User?> get authStateChanges => _auth.authStateChanges();

  static Future<UserCredential> registerWithEmail({
    required String email,
    required String password,
    required String displayName,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user != null) {
      await user.updateDisplayName(displayName);

      // Sincronizar token en Realtime con force refresh para capturar custom claims
      try {
        final token = await user.getIdToken(true);
        if (token != null) {
          await SupabaseService.client.realtime.setAuth(token);
        }
      } catch (_) {}

      // Sincronizar perfil inicial en Supabase
      final profile = UserProfile(
        id: user.uid,
        displayName: displayName,
        bio: '¡Hola! Estoy usando Discord EPN.',
        isOnline: true,
        lastSeen: DateTime.now(),
      );

      try {
        await SupabaseService.upsertProfile(profile);
      } catch (e) {
        throw AppException(
          'Usuario creado en Firebase, pero ocurrió un problema al inicializar el perfil en la base de datos: $e',
          e,
        );
      }
    }

    return credential;
  }

  static Future<UserCredential> loginWithEmail({
    required String email,
    required String password,
  }) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user != null) {
      try {
        final token = await user.getIdToken();
        if (token != null) {
          await SupabaseService.client.realtime.setAuth(token);
        }
      } catch (_) {}

      try {
        await SupabaseService.updatePresence(user.uid, true);
      } catch (_) {}

      // Fallback autorreparador: si por alguna razón no existía perfil, crearlo
      try {
        final existing = await SupabaseService.getProfile(user.uid);
        if (existing == null) {
          final fallbackProfile = UserProfile(
            id: user.uid,
            displayName: user.displayName ?? (user.email?.split('@').first ?? 'Usuario'),
            bio: '¡Hola! Estoy usando Discord EPN.',
            isOnline: true,
            lastSeen: DateTime.now(),
          );
          await SupabaseService.upsertProfile(fallbackProfile);
        }
      } catch (_) {}
    }

    return credential;
  }

  static Future<void> signOut() async {
    final user = currentUser;
    if (user != null) {
      try {
        await SupabaseService.updatePresence(user.uid, false);
      } catch (_) {}
    }

    try {
      await SupabaseService.client.realtime.setAuth(null);
    } catch (_) {}

    await _auth.signOut();
  }
}
