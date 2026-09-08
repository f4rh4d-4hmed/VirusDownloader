import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/core/utils.dart';
import 'package:virusdownloader/domain/models/download_task.dart';

void main() {
  group('AppUtils.extractExtension', () {
    test('extracts clean extension from simple filename', () {
      expect(AppUtils.extractExtension('archive.rar'), equals('rar'));
      expect(AppUtils.extractExtension('app.apk'), equals('apk'));
      expect(AppUtils.extractExtension('song.mp3'), equals('mp3'));
      expect(AppUtils.extractExtension('video.mp4'), equals('mp4'));
      expect(AppUtils.extractExtension('image.png'), equals('png'));
    });

    test('extracts extension from filenames with dots in body (e.g. SteamRIP.com.rar)', () {
      expect(
        AppUtils.extractExtension('Hollow-Knight-Silksong-SteamRIP.com.rar'),
        equals('rar'),
      );
      expect(
        AppUtils.extractExtension('stremy-android-arm64-v8a.apk'),
        equals('apk'),
      );
      expect(
        AppUtils.extractExtension('my.cool.app.v1.0.2.tar.gz'),
        equals('tar.gz'),
      );
    });

    test('strips URL query strings and hash fragments', () {
      expect(
        AppUtils.extractExtension('https://cdn.example.com/file.rar?token=abc&expiry=123'),
        equals('rar'),
      );
      expect(
        AppUtils.extractExtension('https://example.com/path/installer.apk#download'),
        equals('apk'),
      );
      expect(
        AppUtils.extractExtension('file.png?width=200&height=200#top'),
        equals('png'),
      );
    });

    test('handles path separators and numeric duplicate suffixes', () {
      expect(
        AppUtils.extractExtension(r'C:\Downloads\file (1).rar'),
        equals('rar'),
      );
      expect(
        AppUtils.extractExtension('/home/user/downloads/app (2).apk'),
        equals('apk'),
      );
    });

    test('recognizes compound extensions', () {
      expect(AppUtils.extractExtension('archive.tar.gz'), equals('tar.gz'));
      expect(AppUtils.extractExtension('archive.tar.bz2'), equals('tar.bz2'));
      expect(AppUtils.extractExtension('archive.tar.xz'), equals('tar.xz'));
    });

    test('returns empty string for extensionless files', () {
      expect(AppUtils.extractExtension('LICENSE'), equals(''));
      expect(AppUtils.extractExtension('Makefile'), equals(''));
      expect(AppUtils.extractExtension(''), equals(''));
    });
  });

  group('AppUtils.categoryFromExtension', () {
    test('categorizes the user reported browser download files correctly', () {
      expect(
        AppUtils.categoryFromExtension('Hollow-Knight-Silksong-SteamRIP.com.rar'),
        equals(DownloadCategory.compressed),
      );
      expect(
        AppUtils.categoryFromExtension('stremy-android-arm64-v8a.apk'),
        equals(DownloadCategory.programs),
      );
    });

    test('categorizes broad variety of Compressed / Archives', () {
      final archives = [
        'test.zip', 'test.rar', 'test.7z', 'test.tar', 'test.gz',
        'test.bz2', 'test.xz', 'test.iso', 'test.dmg', 'test.tar.gz',
        'test.tgz', 'test.cab', 'test.zst',
      ];
      for (final name in archives) {
        expect(
          AppUtils.categoryFromExtension(name),
          equals(DownloadCategory.compressed),
          reason: '$name should be classified as compressed',
        );
      }
    });

    test('categorizes broad variety of Programs / Executables', () {
      final programs = [
        'setup.exe', 'installer.msi', 'app.apk', 'package.deb',
        'package.rpm', 'app.appimage', 'script.bat', 'script.cmd',
        'script.ps1', 'script.sh', 'mod.jar',
      ];
      for (final name in programs) {
        expect(
          AppUtils.categoryFromExtension(name),
          equals(DownloadCategory.programs),
          reason: '$name should be classified as programs',
        );
      }
    });

    test('categorizes broad variety of Videos', () {
      final videos = [
        'movie.mp4', 'clip.mkv', 'video.avi', 'recording.mov',
        'stream.webm', 'tv.wmv', 'flash.flv', 'dvd.vob',
        'broadcast.ts', 'phone.3gp', 'playlist.m3u8',
      ];
      for (final name in videos) {
        expect(
          AppUtils.categoryFromExtension(name),
          equals(DownloadCategory.videos),
          reason: '$name should be classified as videos',
        );
      }
    });

    test('categorizes broad variety of Audio', () {
      final audios = [
        'track.mp3', 'song.wav', 'music.flac', 'recording.m4a',
        'podcast.ogg', 'tune.aac', 'radio.opus', 'score.mid',
      ];
      for (final name in audios) {
        expect(
          AppUtils.categoryFromExtension(name),
          equals(DownloadCategory.audio),
          reason: '$name should be classified as audio',
        );
      }
    });

    test('categorizes broad variety of Images', () {
      final images = [
        'photo.jpg', 'pic.jpeg', 'graphic.png', 'banner.webp',
        'anim.gif', 'icon.svg', 'fav.ico', 'shot.bmp',
        'raw.cr2', 'apple.heic', 'next.avif',
      ];
      for (final name in images) {
        expect(
          AppUtils.categoryFromExtension(name),
          equals(DownloadCategory.images),
          reason: '$name should be classified as images',
        );
      }
    });

    test('categorizes broad variety of Documents and Code', () {
      final docs = [
        'report.pdf', 'document.docx', 'notes.txt', 'sheet.xlsx',
        'table.csv', 'slides.pptx', 'book.epub', 'readme.md',
        'data.json', 'config.yaml', 'main.dart', 'script.py',
      ];
      for (final name in docs) {
        expect(
          AppUtils.categoryFromExtension(name),
          equals(DownloadCategory.documents),
          reason: '$name should be classified as documents',
        );
      }
    });

    test('returns other for unknown extensions', () {
      expect(AppUtils.categoryFromExtension('blob.unknownextxyz'), equals(DownloadCategory.other));
      expect(AppUtils.categoryFromExtension('noextension'), equals(DownloadCategory.other));
    });
  });

  group('Preview Capability Detection', () {
    test('isImageFormat identifies common previewable images', () {
      expect(AppUtils.isImageFormat('photo.jpg'), isTrue);
      expect(AppUtils.isImageFormat('photo.jpeg'), isTrue);
      expect(AppUtils.isImageFormat('photo.png'), isTrue);
      expect(AppUtils.isImageFormat('photo.webp'), isTrue);
      expect(AppUtils.isImageFormat('photo.gif'), isTrue);
      expect(AppUtils.isImageFormat('photo.bmp'), isTrue);
      expect(AppUtils.isImageFormat('video.mp4'), isFalse);
      expect(AppUtils.isImageFormat('archive.rar'), isFalse);
    });

    test('isAudioFormat identifies common audio formats', () {
      expect(AppUtils.isAudioFormat('song.mp3'), isTrue);
      expect(AppUtils.isAudioFormat('song.wav'), isTrue);
      expect(AppUtils.isAudioFormat('song.flac'), isTrue);
      expect(AppUtils.isAudioFormat('song.m4a'), isTrue);
      expect(AppUtils.isAudioFormat('song.ogg'), isTrue);
      expect(AppUtils.isAudioFormat('song.aac'), isTrue);
      expect(AppUtils.isAudioFormat('video.mp4'), isFalse);
    });

    test('isVideoFormat identifies common video formats', () {
      expect(AppUtils.isVideoFormat('movie.mp4'), isTrue);
      expect(AppUtils.isVideoFormat('movie.mkv'), isTrue);
      expect(AppUtils.isVideoFormat('movie.webm'), isTrue);
      expect(AppUtils.isVideoFormat('movie.avi'), isTrue);
      expect(AppUtils.isVideoFormat('movie.mov'), isTrue);
      expect(AppUtils.isVideoFormat('song.mp3'), isFalse);
    });

    test('canPreview accurately filters previewable vs non-previewable formats', () {
      expect(AppUtils.canPreview('image.png'), isTrue);
      expect(AppUtils.canPreview('song.mp3'), isTrue);
      expect(AppUtils.canPreview('video.mkv'), isTrue);
      expect(AppUtils.canPreview('notes.txt'), isTrue);
      expect(AppUtils.canPreview('code.dart'), isTrue);
      expect(AppUtils.canPreview('package.apk'), isFalse);
      expect(AppUtils.canPreview('archive.rar'), isFalse);
      expect(AppUtils.canPreview('archive.zip'), isFalse);
      expect(AppUtils.canPreview('installer.exe'), isFalse);
    });
  });

  group('DownloadTask Category Repair', () {
    test('task with misassigned video category repairs to compressed for .rar', () {
      final task = DownloadTask(
        id: 'task-1',
        url: 'https://example.com/download?id=123',
        fileName: 'Hollow-Knight-Silksong-SteamRIP.com.rar',
        savePath: r'C:\Downloads\Hollow-Knight-Silksong-SteamRIP.com.rar',
        totalBytes: 4000000000,
        downloadedBytes: 4000000000,
        status: DownloadStatus.completed,
        category: DownloadCategory.videos, // Was incorrectly set as video
        speedBytesPerSec: 0,
        dateAdded: DateTime.now(),
      );

      final extCat = AppUtils.categoryFromExtension(task.fileName);
      expect(extCat, equals(DownloadCategory.compressed));

      final repaired = task.copyWith(category: extCat);
      expect(repaired.category, equals(DownloadCategory.compressed));
    });

    test('task with misassigned video category repairs to programs for .apk', () {
      final task = DownloadTask(
        id: 'task-2',
        url: 'https://example.com/get/apk',
        fileName: 'stremy-android-arm64-v8a.apk',
        savePath: r'C:\Downloads\stremy-android-arm64-v8a.apk',
        totalBytes: 56000000,
        downloadedBytes: 56000000,
        status: DownloadStatus.completed,
        category: DownloadCategory.videos, // Was incorrectly set as video
        speedBytesPerSec: 0,
        dateAdded: DateTime.now(),
      );

      final extCat = AppUtils.categoryFromExtension(task.fileName);
      expect(extCat, equals(DownloadCategory.programs));

      final repaired = task.copyWith(category: extCat);
      expect(repaired.category, equals(DownloadCategory.programs));
    });
  });
}

