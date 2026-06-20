import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:myweli/main.dart';

void main() {
  testWidgets('App boots smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const MyweliApp());
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
