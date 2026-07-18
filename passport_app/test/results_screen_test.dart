import 'dart:typed_data';

import 'package:compliance_core/compliance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:passport_app/screens/results_screen.dart';
import 'package:passport_app/state/app_state.dart';

/// A1-06 / S5 acceptance coverage. Builds a ComplianceReport directly (no ML
/// Kit / camera plugins) so the screen can be pumped in a widget test.

CheckResult _pass(String id, String name, String msg,
        {Severity sev = Severity.error, Object? measured}) =>
    CheckResult(
        checkId: id,
        name: name,
        pass: true,
        severity: sev,
        message: msg,
        measuredValue: measured);

CheckResult _fail(String id, String name, String msg, {Object? measured}) =>
    CheckResult(
        checkId: id,
        name: name,
        pass: false,
        severity: Severity.error,
        message: msg,
        measuredValue: measured);

AppState _stateWith(ComplianceReport report) {
  final s = AppState()..selectDoc(usPassport);
  s.setResult(
      report: report, clean: Uint8List(0), preview: Uint8List(0));
  return s;
}

/// A host with the routes S5 hands off to, each marked so navigation is
/// observable after a tap.
Widget _host(AppState state) => ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        initialRoute: '/results',
        routes: {
          '/results': (_) => const ResultsScreen(),
          '/capture': (_) =>
              const Scaffold(body: Center(child: Text('CAPTURE_SCREEN'))),
          '/preview': (_) =>
              const Scaffold(body: Center(child: Text('PREVIEW_SCREEN'))),
        },
      ),
    );

ComplianceReport _failingReport() => ComplianceReport(
      documentId: 'us_passport',
      results: [
        _pass('C1', 'single-face', 'One face detected.', measured: 1),
        _fail('C3', 'head-height',
            'Move closer, your head is too small in the frame.',
            measured: '30.0% (want 50-69%)'),
        _pass('C9', 'head-covering', 'Head covering guidance.',
            sev: Severity.warning),
      ],
    );

ComplianceReport _passingReport() => ComplianceReport(
      documentId: 'us_passport',
      results: [
        _pass('C1', 'single-face', 'One face detected.', measured: 1),
        _pass('C3', 'head-height', 'Head size looks right.',
            measured: '60.0% (want 50-69%)'),
      ],
    );

Future<void> _pump(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1200, 2600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(state));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('each check shows its status message and measured reason',
      (tester) async {
    await _pump(tester, _stateWith(_failingReport()));

    // The failing check's plain-language reason is shown...
    expect(
        find.text('Move closer, your head is too small in the frame.'),
        findsOneWidget);
    // ...alongside the check id + measured value (the "reason" detail).
    expect(find.textContaining('C3 · 30.0%'), findsOneWidget);
    // Passing requirement is present too.
    expect(find.text('One face detected.'), findsOneWidget);
  });

  testWidgets('S5 offers retake, adjust, and continue', (tester) async {
    await _pump(tester, _stateWith(_failingReport()));
    expect(find.widgetWithText(OutlinedButton, 'Retake'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Adjust'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Continue anyway'), findsOneWidget);
  });

  testWidgets('Retake returns to capture', (tester) async {
    await _pump(tester, _stateWith(_failingReport()));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retake'));
    await tester.pumpAndSettle();
    expect(find.text('CAPTURE_SCREEN'), findsOneWidget);
  });

  testWidgets('Adjust returns to capture', (tester) async {
    await _pump(tester, _stateWith(_failingReport()));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Adjust'));
    await tester.pumpAndSettle();
    expect(find.text('CAPTURE_SCREEN'), findsOneWidget);
  });

  testWidgets('Continue goes to the preview', (tester) async {
    await _pump(tester, _stateWith(_passingReport()));
    expect(find.widgetWithText(FilledButton, 'Continue'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(find.text('PREVIEW_SCREEN'), findsOneWidget);
  });

  testWidgets('a passing report reads as all requirements met', (tester) async {
    await _pump(tester, _stateWith(_passingReport()));
    expect(find.textContaining('All requirements met'), findsOneWidget);
  });

  testWidgets('no acceptance-guarantee wording anywhere on S5 (spec 5)',
      (tester) async {
    await _pump(tester, _stateWith(_passingReport()));
    for (final banned in ['guarantee', 'guaranteed', '100%', 'approval']) {
      expect(
        find.textContaining(RegExp(banned, caseSensitive: false)),
        findsNothing,
        reason: 'spec bans acceptance-guarantee wording: "$banned"',
      );
    }
  });
}
