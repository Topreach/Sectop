import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  testWidgets('DangerEmergenceApp should be created', (WidgetTester tester) async {
    await tester.pumpWidget(const DangerEmergenceApp());
    expect(find.byType(DangerEmergenceApp), findsOneWidget);

    // Pump past the SplashScreen's 3-second timer to avoid pending timer assertion
    await tester.pump(const Duration(seconds: 4));
  });
}
