import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/ui/views/rename_dialog.dart';

void main() {
  testWidgets('RenameDialog validates input and returns full filename with extension', (tester) async {
    String? confirmedName;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                RenameDialog.show(
                  context,
                  'document.pdf',
                  onConfirm: (newName) {
                    confirmedName = newName;
                  },
                );
              },
              child: const Text('Show Dialog'),
            ),
          ),
        ),
      ),
    );

    // Open dialog
    await tester.tap(find.text('Show Dialog'));
    await tester.pumpAndSettle();

    // Verify initial input text is base name without extension
    expect(find.text('document'), findsOneWidget);
    expect(find.text('.pdf'), findsOneWidget);

    // Test invalid empty name
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Filename cannot be empty'), findsOneWidget);
    expect(confirmedName, isNull);

    // Test illegal characters
    await tester.enterText(find.byType(TextField), 'bad/name');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    expect(find.text('Contains illegal characters (\\ / : * ? " < > |)'), findsOneWidget);
    expect(confirmedName, isNull);

    // Test valid rename
    await tester.enterText(find.byType(TextField), 'my_new_doc');
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();

    expect(confirmedName, 'my_new_doc.pdf');
    expect(find.byType(RenameDialog), findsNothing);
  });
}

