import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'core/config/app_config.dart';
import 'core/constants/discord_colors.dart';
import 'core/services/auth_service.dart';
import 'core/services/supabase_service.dart';
import 'core/providers/chat_provider.dart';
import 'ui/auth/login_screen.dart';
import 'ui/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
  };

  ErrorWidget.builder = (details) => _StartupErrorScreen(
    message: 'Ocurrió un error inesperado en la interfaz:\n${details.exception}',
  );

  try {
    // 1. Cargar variables de entorno si están presentes localmente
    try {
      await dotenv.load(fileName: '.env');
    } catch (_) {}

    // Validar configuración de backend (URL y Keys)
    AppConfig.validate();

    // 2. Inicializar Firebase
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    // 3. Inicializar Supabase con Auth bridge (PRIMERO para que el cliente esté listo)
    await SupabaseService.initialize();

    // 4. Inicializar Notificaciones Push (FCM) DESPUÉS de inicializar Supabase
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      // ignore: deprecated_member_use
      final fcmToken = await messaging.getToken();
      if (fcmToken != null) {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid != null) {
          final platform = kIsWeb
              ? 'web'
              : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');
          await SupabaseService.upsertPushToken(
            userId: currentUid,
            token: fcmToken,
            platform: platform,
          );
        }
      }

      // Escuchar renovación de tokens de FCM
      // ignore: deprecated_member_use
      FirebaseMessaging.instance.onTokenRefresh.listen((newToken) async {
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (currentUid != null) {
          final platform = kIsWeb
              ? 'web'
              : (defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android');
          await SupabaseService.upsertPushToken(
            userId: currentUid,
            token: newToken,
            platform: platform,
          );
        }
      });
    } catch (e) {
      debugPrint('Aviso FCM: $e');
    }

    runApp(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ChatProvider()),
        ],
        child: const DiscordEpnApp(),
      ),
    );
  } catch (e) {
    runApp(_StartupErrorScreen(message: 'No se pudo iniciar Discord EPN:\n$e'));
  }
}

class _StartupErrorScreen extends StatelessWidget {
  final String message;
  const _StartupErrorScreen({required this.message});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Discord EPN - Error',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: DiscordColors.chatBackground,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 64, color: DiscordColors.red),
                const SizedBox(height: 16),
                const Text(
                  'Error de Configuración',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class DiscordEpnApp extends StatelessWidget {
  const DiscordEpnApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Discord EPN',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: DiscordColors.chatBackground,
        primaryColor: DiscordColors.blurple,
        colorScheme: const ColorScheme.dark(
          primary: DiscordColors.blurple,
          surface: DiscordColors.channelSidebar,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: DiscordColors.chatBackground,
          elevation: 0,
        ),
        dividerColor: DiscordColors.divider,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? _initializedFor;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: DiscordColors.chatBackground,
            body: Center(
              child: CircularProgressIndicator(color: DiscordColors.blurple),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          _initializedFor = null;
          return const LoginScreen();
        }

        if (_initializedFor != user.uid) {
          _initializedFor = user.uid;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              context.read<ChatProvider>().initializeUser(user.uid);
            }
          });
        }

        return const HomeScreen();
      },
    );
  }
}
