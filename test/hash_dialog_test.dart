import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/data/services/integrity_service.dart';
import 'package:virusdownloader/domain/models/download_task.dart';
import 'package:virusdownloader/ui/views/hash_dialog.dart';

void main() {
  testWidgets('HashDialog initializes with Tap placeholder and does not auto-calculate', (tester) async {
    final task = DownloadTask(
      id: 'test-hash-1',
      url: 'https://example.com/file.bin',
      fileName: 'file.bin',
      savePath: '/tmp/file.bin',
      status: DownloadStatus.completed,
      dateAdded: DateTime.now(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Provider<IntegrityService>.value(
            value: IntegrityService(),
            child: HashDialog(task: task),
          ),
        ),
      ),
    );

    // Initial state: "Tap" placeholder displayed
    expect(find.text('Tap'), findsOneWidget);
    // Placeholder message displayed
    expect(find.text('Select an algorithm to calculate hash'), findsOneWidget);
    // Recalculate button disabled
    final recalcButton = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Recalculate'));
    expect(recalcButton.onPressed, isNull);
  });
}
