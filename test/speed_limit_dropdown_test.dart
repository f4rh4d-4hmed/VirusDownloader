import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/ui/widgets/app_animated_dropdown.dart';
import 'package:virusdownloader/ui/widgets/speed_limit_icon.dart';

void main() {
  group('SpeedLimitIcon Tests', () {
    testWidgets('renders correct icons for all SpeedLimitMode values', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: const [
                SpeedLimitIcon(mode: SpeedLimitMode.rabbit),
                SpeedLimitIcon(mode: SpeedLimitMode.turtle),
                SpeedLimitIcon(mode: SpeedLimitMode.unlimited),
                SpeedLimitIcon(mode: SpeedLimitMode.rocket),
              ],
            ),
          ),
        ),
      );

      // Verify rabbit outline icon exists
      expect(find.byType(RabbitOutlineIcon), findsOneWidget);
      // Verify turtle outline icon exists
      expect(find.byType(TurtleOutlineIcon), findsOneWidget);
      // Verify unlimited icon exists
      expect(find.byIcon(Icons.all_inclusive_rounded), findsOneWidget);
      // Verify rocket icon exists
      expect(find.byIcon(Icons.rocket_launch_outlined), findsOneWidget);
    });

    test('SpeedLimitModeExt provides valid descriptions and labels', () {
      for (final mode in SpeedLimitMode.values) {
        expect(mode.label.isNotEmpty, isTrue);
        expect(mode.description.isNotEmpty, isTrue);
      }
      expect(SpeedLimitMode.rabbit.label, contains('Rabbit'));
      expect(SpeedLimitMode.turtle.label, contains('Turtle'));
      expect(SpeedLimitMode.unlimited.label, contains('Unlimited'));
      expect(SpeedLimitMode.rocket.label, contains('Rocket'));
    });
  });

  group('AppAnimatedDropdown Tests', () {
    testWidgets('renders trigger button with current selection', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppAnimatedDropdown<SpeedLimitMode>(
                value: SpeedLimitMode.rabbit,
                items: SpeedLimitMode.values.map((mode) {
                  return AppDropdownItem<SpeedLimitMode>(
                    value: mode,
                    label: mode.label,
                    subtitle: mode.description,
                    icon: SpeedLimitIcon(mode: mode),
                  );
                }).toList(),
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text(SpeedLimitMode.rabbit.label), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
      expect(find.byType(RabbitOutlineIcon), findsOneWidget);
    });

    testWidgets('tapping opens dropdown menu with animation and items', (tester) async {
      SpeedLimitMode? selectedMode;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: AppAnimatedDropdown<SpeedLimitMode>(
                value: SpeedLimitMode.unlimited,
                items: SpeedLimitMode.values.map((mode) {
                  return AppDropdownItem<SpeedLimitMode>(
                    value: mode,
                    label: mode.label,
                    subtitle: mode.description,
                    icon: SpeedLimitIcon(mode: mode),
                  );
                }).toList(),
                onChanged: (val) {
                  selectedMode = val;
                },
              ),
            ),
          ),
        ),
      );

      // Open dropdown
      await tester.tap(find.text(SpeedLimitMode.unlimited.label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // All options should be visible in the overlay
      expect(find.text(SpeedLimitMode.rabbit.label), findsOneWidget);
      expect(find.text(SpeedLimitMode.turtle.label), findsOneWidget);
      expect(find.text(SpeedLimitMode.rocket.label), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget); // Unlimited is selected

      // Tap on turtle option
      await tester.tap(find.text(SpeedLimitMode.turtle.label));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Check onChanged callback was triggered with turtle
      expect(selectedMode, SpeedLimitMode.turtle);
    });

    testWidgets('tapping outside dismisses the dropdown menu', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                const Text('Outside Area'),
                Center(
                  child: AppAnimatedDropdown<int>(
                    value: 2,
                    items: const [
                      AppDropdownItem(value: 1, label: '1 task'),
                      AppDropdownItem(value: 2, label: '2 tasks'),
                      AppDropdownItem(value: 3, label: '3 tasks'),
                    ],
                    onChanged: (_) {},
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Open dropdown
      await tester.tap(find.text('2 tasks'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('1 task'), findsOneWidget);

      // Tap outside (barrier intercepts and dismisses)
      await tester.tap(find.text('Outside Area'), warnIfMissed: false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Dropdown menu should be closed
      expect(find.text('1 task'), findsNothing);
    });
  });
}
