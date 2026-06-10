import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static const String googleServerClientId =
      '1084030875192-3mnalpia37tp1kjfdtqi13h1v3d4t3kk.apps.googleusercontent.com';
  static const String googleIosClientId =
      '1084030875192-fbos8i5sujd887h3bdbg64vke7c86i26.apps.googleusercontent.com';

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'MacOS configuration not provided',
        );
      case TargetPlatform.windows:
        return web;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'Linux configuration not provided',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: "AIzaSyCeFNVr_xrCqFOBPhTh2AGR9TZ-XuD8w5w",
    appId: "1:1084030875192:web:43234ccb49f2b0ff5058cd",
    messagingSenderId: "1084030875192",
    projectId: "hotel-project-fa6f3",
    authDomain: "hotel-project-fa6f3.firebaseapp.com",
    storageBucket: "hotel-project-fa6f3.firebasestorage.app",
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: "AIzaSyDnAZPJ_gtZDypWjOBpHqd3hbNZAcmtHJY",
    appId: "1:1084030875192:android:123e147d7261b5e35058cd",
    messagingSenderId: "1084030875192",
    projectId: "hotel-project-fa6f3",
    storageBucket: "hotel-project-fa6f3.firebasestorage.app",
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: "AIzaSyDNh0gY2vCGnn4oZcqYCh05CrE3wY-7tKI",
    appId: "1:1084030875192:ios:b3f4c73c2b6b8f5b5058cd",
    messagingSenderId: "1084030875192",
    projectId: "hotel-project-fa6f3",
    storageBucket: "hotel-project-fa6f3.firebasestorage.app",
    iosBundleId: "com.rezzaky.stayfix",
    iosClientId:
        "1084030875192-fbos8i5sujd887h3bdbg64vke7c86i26.apps.googleusercontent.com",
  );
}
