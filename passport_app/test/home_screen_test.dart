import 'package:compliance_core/compliance_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:passport_app/screens/home_screen.dart';
import 'package:passport_app/state/app_state.dart';

/// A1-02 / S2 Home acceptance coverage. Pumps HomeScreen alone so the tests do
/// not depend on the camera plugin behind the /capture route.
Widget _host(AppState state) => ChangeNotifierProvider.value(
      value: state,
      child: const MaterialApp(home: HomeScreen()),
    );

/// The Home screen is a lazily-built ListView; a tall surface keeps every
/// progressive section (country list -> doc list -> spec preview) laid out so
/// finders can see it without scrolling.
Future<void> _pumpHome(WidgetTester tester, AppState state) async {
  tester.view.physicalSize = const Size(1200, 3200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_host(state));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('country search filters the country list', (tester) async {
    await _pumpHome(tester, AppState());

    // Default state: every MVP country is offered.
    expect(find.text('US'), findsOneWidget);
    expect(find.text('India'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'india');
    await tester.pumpAndSettle();

    expect(find.text('India'), findsOneWidget);
    expect(find.text('US'), findsNothing);
  });

  testWidgets('search-with-no-match shows the empty state', (tester) async {
    await _pumpHome(tester, AppState());

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();

    expect(find.textContaining('No countries match'), findsOneWidget);
  });

  testWidgets('selecting country then doc carries the spec forward and '
      'enables Start', (tester) async {
    final state = AppState();
    await _pumpHome(tester, state);

    // Start is disabled until a document is picked.
    expect(find.text('Select a document'), findsOneWidget);

    await tester.tap(find.text('US'));
    await tester.pumpAndSettle();

    // Doc-type list for US appears.
    expect(find.text('US Passport'), findsWidgets);

    await tester.tap(find.text('US Passport').first);
    await tester.pumpAndSettle();

    // Spec preview shows and Start is now enabled.
    expect(find.text('Print size'), findsOneWidget);
    expect(find.text('Start'), findsOneWidget);

    // The correct spec is what will be carried forward on Start.
    state.selectDoc(usPassport);
    expect(state.doc?.id, 'us_passport');
  });

  testWidgets('US doc type flags the verify-and-format-only path (spec 4)',
      (tester) async {
    await _pumpHome(tester, AppState());

    await tester.tap(find.text('US'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('US Passport').first);
    await tester.pumpAndSettle();

    expect(find.textContaining('no AI alteration'), findsOneWidget);
  });

  testWidgets('non-US doc type does NOT show the US no-alteration flag',
      (tester) async {
    await _pumpHome(tester, AppState());

    await tester.tap(find.text('UK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('UK Passport').first);
    await tester.pumpAndSettle();

    expect(find.text('Print size'), findsOneWidget); // preview shown
    expect(find.textContaining('no AI alteration'), findsNothing);
  });

  testWidgets('no guaranteed-acceptance wording anywhere on screen (spec 5)',
      (tester) async {
    await _pumpHome(tester, AppState());

    await tester.tap(find.text('US'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('US Passport').first);
    await tester.pumpAndSettle();

    for (final banned in ['guarantee', 'guaranteed', '100%', 'approval']) {
      expect(find.textContaining(RegExp(banned, caseSensitive: false)),
          findsNothing,
          reason: 'spec 5 bans acceptance-guarantee wording: "$banned"');
    }
  });
}
