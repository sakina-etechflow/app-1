// GENERATED-STYLE PLACEHOLDER — replace with real values.
//
// This file normally comes from the FlutterFire CLI. To wire the app to a real
// Firebase project, run this once (it overwrites this file with real keys):
//
//     dart pub global activate flutterfire_cli
//     flutterfire configure
//
// Until then the values below are placeholders: the app still builds and runs,
// but cloud sign-in / sync stay disabled (AuthService detects the placeholder
// and no-ops). No passport/ID photos are ever uploaded regardless — only
// settings and history metadata sync once real credentials are present.
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// Sentinel used to detect the un-configured placeholder project.
const String kPlaceholderFirebaseProjectId = 'REPLACE_ME_PROJECT_ID';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  /// True while this file still holds placeholder values.
  static bool get isPlaceholder =>
      android.projectId == kPlaceholderFirebaseProjectId;

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'REPLACE_ME_ANDROID_API_KEY',
    appId: '1:000000000000:android:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: kPlaceholderFirebaseProjectId,
    storageBucket: 'REPLACE_ME_PROJECT_ID.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_ME_IOS_API_KEY',
    appId: '1:000000000000:ios:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: kPlaceholderFirebaseProjectId,
    storageBucket: 'REPLACE_ME_PROJECT_ID.appspot.com',
    iosBundleId: 'com.etechflow.passportApp',
  );

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'REPLACE_ME_WEB_API_KEY',
    appId: '1:000000000000:web:0000000000000000000000',
    messagingSenderId: '000000000000',
    projectId: kPlaceholderFirebaseProjectId,
    storageBucket: 'REPLACE_ME_PROJECT_ID.appspot.com',
    authDomain: 'REPLACE_ME_PROJECT_ID.firebaseapp.com',
  );
}
