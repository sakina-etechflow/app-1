import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:passport_app/main.dart';
import 'package:passport_app/state/app_state.dart';

void main() {
  testWidgets('app boots to the splash screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppState(),
        child: const PassportApp(),
      ),
    );
    // Splash shows the brand line before navigation.
    expect(find.text('Passport & ID Photo'), findsOneWidget);
  });
}
