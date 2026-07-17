import 'package:flutter_test/flutter_test.dart';

import 'package:lore_app/main.dart';

void main() {
  testWidgets('shows the empty library state', (tester) async {
    await tester.pumpWidget(const LoreApp());

    expect(find.text('Lore'), findsOneWidget);
    expect(find.text('书库尚未创建'), findsOneWidget);
  });
}
