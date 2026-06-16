import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:smartspend/core/theme/app_theme.dart';

void main() {
  testWidgets('Light theme builds without throwing',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Text('SmartSpend')),
      ),
    );
    expect(find.text('SmartSpend'), findsOneWidget);
  });
}
