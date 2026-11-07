// File generated for Discord EPN Firebase configuration
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyANnWOdGQIl7UJ5I8GqWqs24NCsKvKmQME',
    appId: '1:578464705617:web:bdadc009877ecdd1db1c70',
    messagingSenderId: '578464705617',
    projectId: 'discordepn',
    authDomain: 'discordepn.firebaseapp.com',
    storageBucket: 'discordepn.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBwndG8Jyg4LTQyTW5hBnQyyaJLTukBfgY',
    appId: '1:578464705617:android:0bdee4707c098992db1c70',
    messagingSenderId: '578464705617',
    projectId: 'discordepn',
    storageBucket: 'discordepn.firebasestorage.app',
  );
}
