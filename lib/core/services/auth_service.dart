import 'package:firebase_auth/firebase_auth.dart';
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

      // Sincronizar perfil inicial en Supabase
      final profile = UserProfile(
        id: user.uid,
        displayName: displayName,
        bio: '¡Hola! Estoy usando Discord EPN.',
        isOnline: true,
        lastSeen: DateTime.now(),
      );
      await SupabaseService.upsertProfile(profile);
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
      await SupabaseService.updatePresence(user.uid, true);
    }

    return credential;
  }

  static Future<void> signOut() async {
    final user = currentUser;
    if (user != null) {
      await SupabaseService.updatePresence(user.uid, false);
    }
    await _auth.signOut();
  }
}
