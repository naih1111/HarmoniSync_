import 'package:flutter_test/flutter_test.dart';
import 'package:harmonisync_solfege_trainer/main.dart';

void main() {
  testWidgets('App loads correctly', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const MyApp());

    // Verify that the welcome screen loads
    expect(find.text('Welcome'), findsOneWidget);
  });
}
