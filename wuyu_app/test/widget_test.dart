import 'package:flutter_test/flutter_test.dart';
import 'package:wuyu_app/main.dart';

void main() {
  testWidgets('App renders DevConnectScreen', (WidgetTester tester) async {
    await tester.pumpWidget(const WuyuApp());
    expect(find.text('无域 — Dev Connect'), findsOneWidget);
  });
}
