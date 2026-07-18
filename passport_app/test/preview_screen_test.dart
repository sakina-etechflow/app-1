import 'dart:typed_data';

import 'package:compliance_core/compliance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';

import 'package:passport_app/screens/preview_screen.dart';
import 'package:passport_app/state/app_state.dart';

/// A1-07 / S6 acceptance coverage: the free state shows the watermarked render,
/// the unlocked state shows the clean (no-watermark) render — the exact bytes
/// the export step would write.

/// Two distinguishable real JPEGs so we can assert WHICH one the screen shows.
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

AppState _state({required bool unlocked}) {
  final s = AppState()..selectDoc(usPassport);
  s.setResult(
      report: _passingReport(), clean: _cleanBytes, preview: _previewBytes);
  if (unlocked) s.setUnlocked(true);
  return s;
}

Widget _host(AppState state) => ChangeNotifierProvider.value(
      value: state,
      child: MaterialApp(
        home: const PreviewScreen(),
        routes: {
          '/export': (_) =>
              const Scaffold(body: Center(child: Text('EXPORT_SCREEN'))),
          '/paywall': (_) =>
              const Scaffold(body: Center(child: Text('PAYWALL_SCREEN'))),
        },
      ),
    );

/// The bytes actually handed to the on-screen Image.memory widget.
Uint8List _shownBytes(WidgetTester tester) {
  final image = tester.widget<Image>(find.byType(Image));
  return (image.image as MemoryImage).bytes;
}

void main() {
  testWidgets('free state shows the watermarked render', (tester) async {
    await tester.pumpWidget(_host(_state(unlocked: false)));
    await tester.pumpAndSettle();

    expect(_shownBytes(tester), equals(_previewBytes));
    expect(_shownBytes(tester), isNot(equals(_cleanBytes)));
    expect(find.text('Free preview includes a watermark.'), findsOneWidget);
  });

  testWidgets('unlocked state shows the clean, no-watermark render',
      (tester) async {
    await tester.pumpWidget(_host(_state(unlocked: true)));
    await tester.pumpAndSettle();

    expect(_shownBytes(tester), equals(_cleanBytes));
    expect(_shownBytes(tester), isNot(equals(_previewBytes)));
    expect(find.text('Unlocked — export without watermark.'), findsOneWidget);
  });

  testWidgets('free export routes to the paywall', (tester) async {
    await tester.pumpWidget(_host(_state(unlocked: false)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Export photo'));
    await tester.pumpAndSettle();
    expect(find.text('PAYWALL_SCREEN'), findsOneWidget);
  });

  testWidgets('unlocked export routes straight to export', (tester) async {
    await tester.pumpWidget(_host(_state(unlocked: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Export photo'));
    await tester.pumpAndSettle();
    expect(find.text('EXPORT_SCREEN'), findsOneWidget);
  });

  testWidgets('a rewarded unlock also drops the watermark', (tester) async {
    final s = AppState()..selectDoc(usPassport);
    s.setResult(
        report: _passingReport(), clean: _cleanBytes, preview: _previewBytes);
    s.grantRewardedExport(); // single-export unlock via rewarded video

    await tester.pumpWidget(_host(s));
    await tester.pumpAndSettle();

    expect(_shownBytes(tester), equals(_cleanBytes));
    expect(find.text('Unlocked — export without watermark.'), findsOneWidget);
  });
}
