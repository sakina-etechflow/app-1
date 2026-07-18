import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'screens/capture_screen.dart';
import 'screens/export_screen.dart';
import 'screens/home_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/preview_screen.dart';
import 'screens/processing_screen.dart';
import 'screens/results_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/sync_service.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Firebase. Wrapped so a missing/placeholder config or an init
  // failure never blocks the app — cloud sync simply stays off. Photos are
  // never uploaded regardless of this.
  var firebaseReady = false;
  if (!DefaultFirebaseOptions.isPlaceholder) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      firebaseReady = true;
    } catch (e) {
      debugPrint('Firebase init failed, cloud sync disabled: $e');
    }
  } else {
    debugPrint('Firebase not configured (placeholder); cloud sync disabled.');
  }

  final auth = AuthService(available: firebaseReady);
  final sync = SyncService(enabled: firebaseReady);
  await auth.init();

  final appState = AppState()..attachSync(auth: auth, sync: sync);
  // Pull any previously-synced preferences for the signed-in account.
  await appState.hydrateFromCloud();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthService>.value(value: auth),
        Provider<SyncService>.value(value: sync),
        ChangeNotifierProvider<AppState>.value(value: appState),
      ],
      child: const PassportApp(),
    ),
  );
}

class PassportApp extends StatelessWidget {
  const PassportApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Passport & ID Photo',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      initialRoute: '/',
      routes: {
        '/': (_) => const SplashScreen(),
        '/home': (_) => const HomeScreen(),
        '/capture': (_) => const CaptureScreen(),
        '/processing': (_) => const ProcessingScreen(),
        '/results': (_) => const ResultsScreen(),
        '/preview': (_) => const PreviewScreen(),
        '/paywall': (_) => const PaywallScreen(),
        '/export': (_) => const ExportScreen(),
        '/settings': (_) => const SettingsScreen(),
      },
    );
  }
}
