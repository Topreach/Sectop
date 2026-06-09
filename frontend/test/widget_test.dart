import 'package:flutter_test/flutter_test.dart';
import '../lib/main.dart';

void main() {
  testWidgets('DangerEmergenceApp should be created', (WidgetTester tester) async {
    await tester.pumpWidget(const DangerEmergenceApp());
    expect(find.byType(DangerEmergenceApp), findsOneWidget);
  });
}
