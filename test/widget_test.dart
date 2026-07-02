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

  // Regression: [primary] is forced deep green in both brightnesses, so
  // onPrimary must stay light or text on the green hero card / filled
  // buttons becomes unreadable in dark mode.
  test('onPrimary is white in both light and dark themes', () {
    expect(AppTheme.light().colorScheme.onPrimary, Colors.white);
    expect(AppTheme.dark().colorScheme.onPrimary, Colors.white);
  });
}
