import 'package:flutter_test/flutter_test.dart';
import 'package:pure_tube/main.dart';

void main() {
  testWidgets('PureTube smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PureTubeApp(ytJsCode: '', ytCssCode: ''));
    expect(find.byType(PureTubeApp), findsOneWidget);
  });
}
