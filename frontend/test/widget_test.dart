import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mandai_merchandise/widgets/store_widgets.dart';

void main() {
  testWidgets('Store search bar renders and accepts text', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: StoreSearchBar(
      controller: controller,
      onChanged: (_) {},
      onSubmitted: (_) {},
      onClear: () => controller.clear(),
    ))));
    expect(find.byType(TextField), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'panda');
    expect(controller.text, 'panda');
  });
}
