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
        throw UnsupportedError(
          'Android uses google-services.json configuration.',
        );
      case TargetPlatform.iOS:
        throw UnsupportedError(
          'iOS uses GoogleService-Info.plist configuration.',
        );
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
}
