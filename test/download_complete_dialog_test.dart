import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/core/theme.dart';
import 'package:virusdownloader/data/services/file_service.dart';
import 'package:virusdownloader/domain/models/download_task.dart';
import 'package:virusdownloader/ui/views/download_complete_dialog.dart';

class FakeFileService extends Fake implements FileService {
  @override
  Future<bool> openFile(String filePath) async => true;

  @override
  Future<bool> openContainingFolder(String filePath) async => true;
}

void main() {
  late DownloadTask testTask;
  late FileService fakeFileService;

  setUp(() {
    testTask = DownloadTask(
      id: 'test-1',
      url: 'https://example.com/file.zip',
      fileName: 'file.zip',
      savePath: '/downloads/file.zip',
      status: DownloadStatus.completed,
      totalBytes: 1024 * 1024, // 1 MB
      downloadedBytes: 1024 * 1024,
      dateAdded: DateTime(2024, 1, 1),
    );
    fakeFileService = FakeFileService();
  });

  Widget buildTestApp({required DownloadTask task}) {
    return MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            return ElevatedButton(
              onPressed: () => DownloadCompleteDialog.show(
                context,
                task: task,
                fileService: fakeFileService,
              ),
              child: const Text('Show Dialog'),
            );
          },
        ),
      ),
    );
  }

  group('DownloadCompleteDialog Accessibility', () {
    testWidgets('meets accessibility contrast guidelines', (tester) async {
      await tester.pumpWidget(buildTestApp(task: testTask));
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify that the dialog uses the theme's completed color,
      // not hardcoded Colors.green
      final iconFinder = find.byIcon(Icons.check_circle_rounded);
      expect(iconFinder, findsOneWidget);
      final icon = tester.widget<Icon>(iconFinder);
      // Should be DownloadStatusColors.light.completed (0xFF198754), not Colors.green
      expect(icon.color, isNot(Colors.green));
      expect(icon.color, equals(const Color(0xFF198754)));
    });

    testWidgets('decorative icon is excluded from semantics', (tester) async {
      await tester.pumpWidget(buildTestApp(task: testTask));
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // The check circle icon should be wrapped in ExcludeSemantics
      final excludeSemantics = find.ancestor(
        of: find.byIcon(Icons.check_circle_rounded),
        matching: find.byType(ExcludeSemantics),
      );
      expect(excludeSemantics, findsOneWidget);
    });

    testWidgets('metadata rows have descriptive semantics labels',
        (tester) async {
      await tester.pumpWidget(buildTestApp(task: testTask));
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Verify file name semantics
      expect(
        find.bySemanticsLabel(RegExp(r'File name: file\.zip')),
        findsOneWidget,
      );

      // Verify total size semantics
      expect(
        find.bySemanticsLabel(RegExp(r'Total size: ')),
        findsOneWidget,
      );

      // Verify save path semantics
      expect(
        find.bySemanticsLabel(RegExp(r'Saved to: /downloads/file\.zip')),
        findsOneWidget,
      );
    });

    testWidgets('savePath supports multiple lines (not clipped at 1)',
        (tester) async {
      final longPathTask = DownloadTask(
        id: 'test-2',
        url: 'https://example.com/file.zip',
        fileName: 'file.zip',
        savePath: '/very/long/nested/directory/path/that/would/clip/file.zip',
        status: DownloadStatus.completed,
        totalBytes: 1024,
        downloadedBytes: 1024,
        dateAdded: DateTime(2024, 1, 1),
      );

      await tester.pumpWidget(buildTestApp(task: longPathTask));
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Find the save path text widget and verify maxLines > 1
      final textFinder = find.text(longPathTask.savePath);
      expect(textFinder, findsOneWidget);
      final text = tester.widget<Text>(textFinder);
      expect(text.maxLines, greaterThan(1));
    });

    testWidgets('action buttons have overflow direction set', (tester) async {
      await tester.pumpWidget(buildTestApp(task: testTask));
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      final dialogFinder = find.byType(AlertDialog);
      expect(dialogFinder, findsOneWidget);
      final dialog = tester.widget<AlertDialog>(dialogFinder);
      expect(dialog.actionsOverflowDirection, VerticalDirection.down);
      expect(dialog.actionsOverflowButtonSpacing, 8);
    });

    testWidgets('dialog content is scrollable', (tester) async {
      await tester.pumpWidget(buildTestApp(task: testTask));
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      // Content should be wrapped in SingleChildScrollView
      final scrollViewFinder = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollViewFinder, findsOneWidget);
    });

    testWidgets('dismiss button closes dialog', (tester) async {
      await tester.pumpWidget(buildTestApp(task: testTask));
      await tester.tap(find.text('Show Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);
      await tester.tap(find.text('Dismiss'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    });
  });
}
