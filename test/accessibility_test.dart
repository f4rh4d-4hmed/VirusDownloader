import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/core/theme.dart';
import 'package:virusdownloader/data/services/file_service.dart';
import 'package:virusdownloader/data/services/http_download_service.dart';
import 'package:virusdownloader/domain/models/download_task.dart';
import 'package:virusdownloader/ui/views/change_download_link_dialog.dart';
import 'package:virusdownloader/ui/views/download_tile.dart';

Widget createTileWrapper({
  required DownloadTask task,
  VoidCallback? onPause,
  VoidCallback? onResume,
  VoidCallback? onRetry,
  TextScaler? textScaler,
  FocusNode? focusNode,
}) {
  return MaterialApp(
    theme: ThemeData(
      useMaterial3: true,
      extensions: const [DownloadStatusColors.light],
    ),
    home: MediaQuery(
      data: MediaQueryData(
        textScaler: textScaler ?? TextScaler.noScaling,
        size: const Size(800, 600),
      ),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 600,
            child: DownloadTile(
              task: task,
              fileService: FileService(),
              onPause: onPause ?? () {},
              onResume: onResume ?? () {},
              onCancel: () {},
              onRetry: onRetry ?? () {},
              onRemove: () {},
              onDeleteFile: () {},
              focusNode: focusNode,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final activeTask = DownloadTask(
    id: 'a11y-task-1',
    url: 'https://cdn.example.com/files/video.mp4',
    fileName: 'Sample Very Long Video Name For Accessibility Testing.mp4',
    savePath: 'C:\\downloads\\video.mp4',
    totalBytes: 2000,
    downloadedBytes: 1000,
    speedBytesPerSec: 250000,
    status: DownloadStatus.downloading,
    dateAdded: DateTime.now(),
  );

  group('Accessibility Guidelines & Semantics Tests', () {
    testWidgets('DownloadTile meets labeled tap target guideline', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(createTileWrapper(task: activeTask));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      handle.dispose();
    });

    testWidgets('DownloadTile meets Android and iOS tap target guidelines', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(createTileWrapper(task: activeTask));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));

      handle.dispose();
    });

    testWidgets('LinearProgressIndicator provides accessible label and value', (tester) async {
      await tester.pumpWidget(createTileWrapper(task: activeTask));
      await tester.pumpAndSettle();

      final progressFinder = find.byType(LinearProgressIndicator);
      expect(progressFinder, findsOneWidget);

      final progressWidget = tester.widget<LinearProgressIndicator>(progressFinder);
      expect(progressWidget.semanticsLabel, contains(activeTask.fileName));
      expect(progressWidget.semanticsValue, '50%');
    });

    testWidgets('DownloadTile root exposes accessible summary semantics', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(createTileWrapper(task: activeTask));
      await tester.pumpAndSettle();

      final semantics = tester.getSemantics(find.byType(DownloadTile));
      expect(semantics.label, contains(activeTask.fileName));
      expect(semantics.label, contains('downloading'));
      expect(semantics.hint, contains('Shift+F10'));

      handle.dispose();
    });
  });

  group('Keyboard Navigation Tests', () {
    testWidgets('Pressing ContextMenu key on focused tile opens options menu', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(
        createTileWrapper(task: activeTask, focusNode: focusNode),
      );
      await tester.pumpAndSettle();

      focusNode.requestFocus();
      await tester.pump();

      // Send ContextMenu key
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();

      // Options popup menu should be open
      expect(find.text('Pause'), findsWidgets);
      expect(find.text('Copy Download Link'), findsOneWidget);

      focusNode.dispose();
    });

    testWidgets('Pressing Shift+F10 on focused tile opens options menu', (tester) async {
      final focusNode = FocusNode();
      await tester.pumpWidget(
        createTileWrapper(task: activeTask, focusNode: focusNode),
      );
      await tester.pumpAndSettle();

      focusNode.requestFocus();
      await tester.pump();

      // Send Shift + F10
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();

      // Options popup menu should be open
      expect(find.text('Pause'), findsWidgets);
      expect(find.text('Copy Download Link'), findsOneWidget);

      focusNode.dispose();
    });

    testWidgets('Pressing Space key on focused tile triggers primary action', (tester) async {
      final focusNode = FocusNode();
      bool paused = false;
      await tester.pumpWidget(
        createTileWrapper(
          task: activeTask,
          focusNode: focusNode,
          onPause: () => paused = true,
        ),
      );
      await tester.pumpAndSettle();

      focusNode.requestFocus();
      await tester.pump();

      // Send Space key
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();

      expect(paused, isTrue);

      focusNode.dispose();
    });
  });

  group('Text Scaling & Dialog Tap Target Tests', () {
    testWidgets('DownloadTile adapts to 2.0x text scaling without layout overflow', (tester) async {
      await tester.pumpWidget(
        createTileWrapper(
          task: activeTask,
          textScaler: const TextScaler.linear(2.0),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('Sample Very Long'), findsOneWidget);
    });

    testWidgets('ChangeDownloadLinkDialog has accessible expandable header and action buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            extensions: const [DownloadStatusColors.light],
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => ChangeDownloadLinkDialog(
                      task: activeTask,
                      httpService: HttpDownloadService(),
                      onConfirm: (newUrl, [headers, restart = false]) {},
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify the expandable header has at least 48 dp height tap target
      final expandableHeaderFinder = find.text('Advanced: Referer & HTTP Headers');
      expect(expandableHeaderFinder, findsOneWidget);

      final inkWellFinder = find.ancestor(
        of: expandableHeaderFinder,
        matching: find.byType(InkWell),
      );
      expect(inkWellFinder, findsOneWidget);

      final headerSize = tester.getSize(inkWellFinder);
      expect(headerSize.height, greaterThanOrEqualTo(48.0));

      // Tap to expand advanced fields
      await tester.tap(inkWellFinder);
      await tester.pumpAndSettle();

      expect(find.text('Referer Header (Webpage URL)'), findsOneWidget);

      // Verify suffix action buttons (Clear & Paste) have >= 48x48 tap targets
      final pasteButton = find.byTooltip('Paste');
      expect(pasteButton, findsOneWidget);
      final pasteSize = tester.getSize(pasteButton);
      expect(pasteSize.width, greaterThanOrEqualTo(48.0));
      expect(pasteSize.height, greaterThanOrEqualTo(48.0));

      final clearButton = find.byTooltip('Clear URL');
      expect(clearButton, findsOneWidget);
      final clearSize = tester.getSize(clearButton);
      expect(clearSize.width, greaterThanOrEqualTo(48.0));
      expect(clearSize.height, greaterThanOrEqualTo(48.0));

      // Close dialog
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('Pressing Enter key on focused tile triggers primary action', (tester) async {
      final focusNode = FocusNode();
      bool paused = false;
      await tester.pumpWidget(
        createTileWrapper(
          task: activeTask,
          focusNode: focusNode,
          onPause: () => paused = true,
        ),
      );
      await tester.pumpAndSettle();

      focusNode.requestFocus();
      await tester.pump();

      // Send Enter key
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(paused, isTrue);

      focusNode.dispose();
    });

    testWidgets('ChangeDownloadLinkDialog adapts to 2.0x text scaling without layout overflow', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            extensions: const [DownloadStatusColors.light],
          ),
          home: MediaQuery(
            data: const MediaQueryData(
              textScaler: TextScaler.linear(2.0),
              size: Size(1200, 900),
            ),
            child: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => ChangeDownloadLinkDialog(
                        task: activeTask,
                        httpService: HttpDownloadService(),
                        onConfirm: (newUrl, [headers, restart = false]) {},
                      ),
                    );
                  },
                  child: const Text('Open Dialog'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Change Download Link'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    });

    testWidgets('ChangeDownloadLinkDialog meets labeled tap target guideline', (tester) async {
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            useMaterial3: true,
            extensions: const [DownloadStatusColors.light],
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => ChangeDownloadLinkDialog(
                      task: activeTask,
                      httpService: HttpDownloadService(),
                      onConfirm: (newUrl, [headers, restart = false]) {},
                    ),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      handle.dispose();
    });
  });
}
