import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/core/app_scroll_behavior.dart';

void main() {
  test('AppScrollBehavior allows mouse drag scrolling and trackpad gestures', () {
    const behavior = AppScrollBehavior();
    final dragDevices = behavior.dragDevices;

    expect(dragDevices, contains(PointerDeviceKind.mouse));
    expect(dragDevices, contains(PointerDeviceKind.touch));
    expect(dragDevices, contains(PointerDeviceKind.trackpad));
  });

  testWidgets('AppScrollBehavior does not inject conflicting duplicate scrollbars', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            return const AppScrollBehavior().buildScrollbar(
              context,
              const SizedBox(key: Key('scroll-child')),
              ScrollableDetails.vertical(),
            );
          },
        ),
      ),
    );

    expect(find.byKey(const Key('scroll-child')), findsOneWidget);
    expect(find.byType(Scrollbar), findsNothing);
  });
}
