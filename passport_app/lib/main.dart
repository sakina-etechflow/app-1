import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'screens/capture_screen.dart';
import 'screens/export_screen.dart';
import 'screens/home_screen.dart';
import 'screens/paywall_screen.dart';
import 'screens/preview_screen.dart';
import 'screens/processing_screen.dart';
import 'screens/results_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/splash_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ChangeNotifierProvider(
      create: (_) => AppState(),
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
