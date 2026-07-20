import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:passport_app/screens/paywall_screen.dart';
import 'package:passport_app/state/app_state.dart';

/// A1-08 / S7 acceptance coverage. The paywall must, before any purchase:
/// show the full price, offer Restore, offer the watch-ad path, link Terms and
/// Privacy, and never use external-payment or subscription language. Buy /
/// watch-ad / restore all hit the store & ad singletons, so those flows are
/// exercised on-device (see docs/A8-billing-setup.md); here we assert the
/// render contract that the acceptance criteria pin down.

Widget _host() => ChangeNotifierProvider.value(
      value: AppState(),
      child: MaterialApp(
        home: const PaywallScreen(),
        routes: {
          '/export': (_) =>
              const Scaffold(body: Center(child: Text('EXPORT_SCREEN'))),
        },
      ),
    );

void main() {
  // The paywall is a ListView; a tall viewport builds every row (Restore and
  // the legal footer sit at the bottom).
  Future<void> pumpPaywall(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();
  }

  testWidgets('shows the full price up front, before any purchase',
      (tester) async {
    await pumpPaywall(tester);
    // Default price when the SKU is not yet live is $5.99 (BillingService).
    // It appears both in the explicit line and on the buy button.
    expect(find.textContaining(r'$5.99'), findsWidgets);
    expect(find.textContaining('One-time payment'), findsOneWidget);
  });

  testWidgets('offers buy, watch-ad, and Restore paths', (tester) async {
    await pumpPaywall(tester);
    expect(find.widgetWithText(FilledButton, 'Unlock everything — \$5.99'),
        findsOneWidget);
    expect(find.textContaining('Watch a short ad'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Restore Purchases'), findsOneWidget);
  });

  testWidgets('links Terms of Service and Privacy Policy', (tester) async {
    await pumpPaywall(tester);
    expect(find.widgetWithText(TextButton, 'Terms of Service'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Privacy Policy'), findsOneWidget);
  });

  testWidgets('uses one-time, no-subscription language (no external payment)',
      (tester) async {
    await pumpPaywall(tester);
    expect(find.textContaining('No subscription'), findsOneWidget);
    expect(find.textContaining('Not a subscription'), findsOneWidget);
    // Must not imply payment happens anywhere but the store.
    expect(find.textContaining('PayPal'), findsNothing);
    expect(find.textContaining('credit card'), findsNothing);
  });
}
