import 'package:flutter_test/flutter_test.dart';

import 'package:walkable/main.dart';

void main() {
  testWidgets('WalkableApp renders title', (WidgetTester tester) async {
    await tester.pumpWidget(const WalkableApp());
    expect(find.text('Walkable'), findsWidgets);
  });
}
