import 'dart:typed_data';

import 'package:compliance_core/compliance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import 'package:passport_app/screens/export_screen.dart';
import 'package:passport_app/state/app_state.dart';

/// A1-09 / S8 acceptance coverage. Export is unlocked after purchase OR a
/// rewarded view; it saves/shares the full-res, no-watermark image and offers a
/// 4x6 print sheet. A locked user is bounced to unlock. (Share/print and the
/// post-export interstitial hit plugins, so those run on-device; here we assert
/// the gate and that the clean bytes are what the screen exports.)

final Uint8List _cleanBytes = Uint8List.fromList(
    img.encodeJpg(img.Image(width: 4, height: 4)..clear(img.ColorRgb8(10, 200, 10))));
final Uint8List _previewBytes = Uint8List.fromList(
    img.encodeJpg(img.Image(width: 4, height: 4)..clear(img.ColorRgb8(200, 10, 10))));

ComplianceReport _report() => ComplianceReport(
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

AppState _state({bool unlocked = false, bool rewarded = false}) {
  final s = AppState()..selectDoc(usPassport);
  s.setResult(report: _report(), clean: _cleanBytes, preview: _previewBytes);
  if (unlocked) s.setUnlocked(true);
  if (rewarded) s.grantRewardedExport();
  return s;
}

Widget _host(AppState state) => ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        home: const ExportScreen(),
        routes: {
          '/paywall': (_) =>
              const Scaffold(body: Center(child: Text('PAYWALL_SCREEN'))),
        },
      ),
    );

Uint8List _shownBytes(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  return (image.image as MemoryImage).bytes;
}

void main() {
  testWidgets('a locked user cannot export and is offered unlock',
      (tester) async {
    await tester.pumpWidget(_host(_state(unlocked: false)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Unlock first'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Unlock'), findsOneWidget);
    // No export actions are offered while locked.
    expect(find.text('Save / share photo'), findsNothing);
    expect(find.text('Print sheet (4×6 PDF)'), findsNothing);
  });

  testWidgets('a purchased user exports the clean, no-watermark image',
      (tester) async {
    await tester.pumpWidget(_host(_state(unlocked: true)));
    await tester.pumpAndSettle();

    expect(_shownBytes(tester), equals(_cleanBytes));
    expect(_shownBytes(tester), isNot(equals(_previewBytes)));
    expect(find.widgetWithText(FilledButton, 'Save / share photo'),
        findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Print sheet (4×6 PDF)'),
        findsOneWidget);
  });

  testWidgets('a rewarded view also unlocks export of the clean image',
      (tester) async {
    await tester.pumpWidget(_host(_state(rewarded: true)));
    await tester.pumpAndSettle();

    expect(_shownBytes(tester), equals(_cleanBytes));
    expect(find.widgetWithText(FilledButton, 'Save / share photo'),
        findsOneWidget);
  });
}
