import 'dart:typed_data';

import 'package:compliance_core/compliance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import 'package:passport_app/screens/export_screen.dart';
import 'package:passport_app/screens/paywall_screen.dart';
import 'package:passport_app/screens/preview_screen.dart';
import 'package:passport_app/screens/results_screen.dart';
import 'package:passport_app/state/app_state.dart';

/// A1-10 acceptance: the whole flow from the compliance result through to a
/// no-watermark export works end to end, with the paywall gate in between.
///
/// Capture (S3) and on-device processing (S4) need the camera / ML Kit plugins
/// and are covered by the on-device run; this drives the exportable half through
/// the REAL screens (Results -> Preview -> Paywall -> Export) with a seeded
/// AppState, exercising the actual entitlement gating decisions in the screens.

final Uint8List _cleanBytes = Uint8List.fromList(
    img.encodeJpg(img.Image(width: 4, height: 4)..clear(img.ColorRgb8(10, 200, 10))));
final Uint8List _previewBytes = Uint8List.fromList(
    img.encodeJpg(img.Image(width: 4, height: 4)..clear(img.ColorRgb8(200, 10, 10))));

ComplianceReport _passingReport() => ComplianceReport(
      documentId: 'us_passport',
      results: [
        CheckResult(
          checkId: 'C1',
          name: 'single-face',
          pass: true,
          severity: Severity.error,
          message: 'One face detected.',
          measuredValue: 1,
        ),
      ],
    );

/// The real route table for the exportable half of the flow, wired to the real
/// screens. Capture/home are stubs so nav never dead-ends.
Widget _app(AppState state) => ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        initialRoute: '/results',
        routes: {
          '/home': (_) =>
              const Scaffold(body: Center(child: Text('HOME_SCREEN'))),
          '/capture': (_) =>
              const Scaffold(body: Center(child: Text('CAPTURE_SCREEN'))),
          '/results': (_) => const ResultsScreen(),
          '/preview': (_) => const PreviewScreen(),
          '/paywall': (_) => const PaywallScreen(),
          '/export': (_) => const ExportScreen(),
        },
      ),
    );

/// Bytes shown by the Image inside a specific screen. Scoped because pushNamed
/// keeps earlier screens (and their images) mounted beneath the current one.
Uint8List _bytesIn(WidgetTester tester, Finder screen) {
  final image = tester.widget<Image>(
      find.descendant(of: screen, matching: find.byType(Image)));
  return (image.image as MemoryImage).bytes;
}

void main() {
  testWidgets(
      'Home-to-export flow: results -> preview (watermarked) -> paywall -> '
      'unlock -> export (clean)', (tester) async {
    // Seed the state a completed capture + processing would have produced.
    final state = AppState()..selectDoc(usPassport);
    state.setResult(
        report: _passingReport(), clean: _cleanBytes, preview: _previewBytes);

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    // S5 Results — a passing report lets the user continue.
    expect(find.byType(ResultsScreen), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();

    // S6 Preview — free/locked state shows the WATERMARKED render.
    expect(find.byType(PreviewScreen), findsOneWidget);
    expect(_bytesIn(tester, find.byType(PreviewScreen)), equals(_previewBytes));

    // Export from the locked state routes to the paywall (S7), not export.
    await tester.tap(find.widgetWithText(FilledButton, 'Export photo'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsOneWidget);
    // Full price is shown before any purchase (acceptance carried from A1-08).
    expect(find.textContaining(r'$5.99'), findsWidgets);

    // Simulate the purchase completing (billing stream -> AppState.setUnlocked).
    state.setUnlocked(true);
    await tester.pumpAndSettle();

    // Back on preview, the entitlement now shows the CLEAN render...
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PreviewScreen), findsOneWidget);
    expect(_bytesIn(tester, find.byType(PreviewScreen)), equals(_cleanBytes));

    // ...and export now goes straight through to the export screen.
    await tester.tap(find.widgetWithText(FilledButton, 'Export photo'));
    await tester.pumpAndSettle();
    expect(find.byType(ExportScreen), findsOneWidget);
    expect(_bytesIn(tester, find.byType(ExportScreen)), equals(_cleanBytes));
    expect(find.widgetWithText(FilledButton, 'Save / share photo'),
        findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Print sheet (4×6 PDF)'),
        findsOneWidget);
  });

  testWidgets('a rewarded unlock carries the same flow through to export',
      (tester) async {
    final state = AppState()..selectDoc(usPassport);
    state.setResult(
        report: _passingReport(), clean: _cleanBytes, preview: _previewBytes);
    state.grantRewardedExport(); // as if the user watched the rewarded video

    await tester.pumpWidget(_app(state));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    // Preview already unlocked (rewarded) -> clean render, export goes direct.
    expect(_bytesIn(tester, find.byType(PreviewScreen)), equals(_cleanBytes));
    await tester.tap(find.widgetWithText(FilledButton, 'Export photo'));
    await tester.pumpAndSettle();
    expect(find.byType(ExportScreen), findsOneWidget);
  });
}
