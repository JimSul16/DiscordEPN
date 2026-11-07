import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'core/constants/discord_colors.dart';
import 'core/services/auth_service.dart';
import 'core/services/supabase_service.dart';
import 'core/providers/chat_provider.dart';
import 'ui/auth/login_screen.dart';
import 'ui/home/home_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Cargar variables de entorno (.env)
  await dotenv.load(fileName: '.env');

  // 2. Inicializar Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // 3. Inicializar Notificaciones Push (FCM)
  try {
    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    // ignore: deprecated_member_use
    final fcmToken = await messaging.getToken();
    if (kDebugMode) {
      print('FCM Token registrado: $fcmToken');
    }
  } catch (e) {
    if (kDebugMode) {
      print('Aviso FCM: $e');
    }
  }

  // 4. Inicializar Supabase (PostgreSQL + Realtime)
  await SupabaseService.initialize();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ChatProvider()),
      ],
      child: const DiscordEpnApp(),
    ),
  );
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

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

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
          return const LoginScreen();
        }

        // Inicializar estado de usuario en ChatProvider
        final chatProvider = context.read<ChatProvider>();
        if (chatProvider.currentUserProfile == null ||
            chatProvider.currentUserProfile?.id != user.uid) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            chatProvider.initializeUser(user.uid);
          });
        }

        return const HomeScreen();
      },
    );
  }
}
