import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:virusdownloader/data/services/ffmpeg_service.dart';
import 'package:virusdownloader/data/services/hls_download_service.dart';

class MockFfmpegService extends FfmpegService {
  String? lastConcatListPath;
  String? lastOutputPath;
  bool remuxResult = true;

  @override
  Future<bool> remuxConcatList({
    required String concatListPath,
    required String outputPath,
  }) async {
    lastConcatListPath = concatListPath;
    lastOutputPath = outputPath;
    // Create an empty output file so existence check passes
    final outFile = File(outputPath);
    await outFile.writeAsString('mock-remuxed-video');
    return remuxResult;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('HLS Playlist Parsing Tests', () {
    test('parseMasterPlaylist correctly extracts quality variants and resolves relative URLs', () {
      const masterContent = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,CODECS="avc1.4d401f,mp4a.40.2"
360p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=842x480,NAME="480p"
/streams/480p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720,CODECS="avc1.4d401f,mp4a.40.2",NAME="720p"
https://cdn2.example.com/hls/720p.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,CODECS="avc1.640028,mp4a.40.2",NAME="1080p"
1080p/index.m3u8
''';

      final baseUri = Uri.parse('https://cdn.example.com/live/hls/master.m3u8');
      final variants = HlsDownloadService.parseMasterPlaylist(masterContent, baseUri);

      expect(variants.length, equals(4));

      // 360p
      expect(variants[0].bandwidth, equals(800000));
      expect(variants[0].resolution, equals('640x360'));
      expect(variants[0].url, equals('https://cdn.example.com/live/hls/360p.m3u8'));

      // 480p (root-relative)
      expect(variants[1].bandwidth, equals(1400000));
      expect(variants[1].resolution, equals('842x480'));
      expect(variants[1].name, equals('480p'));
      expect(variants[1].url, equals('https://cdn.example.com/streams/480p.m3u8'));

      // 720p (absolute URL)
      expect(variants[2].bandwidth, equals(2800000));
      expect(variants[2].resolution, equals('1280x720'));
      expect(variants[2].url, equals('https://cdn2.example.com/hls/720p.m3u8'));

      // 1080p
      expect(variants[3].bandwidth, equals(5000000));
      expect(variants[3].resolution, equals('1920x1080'));
      expect(variants[3].url, equals('https://cdn.example.com/live/hls/1080p/index.m3u8'));
    });

    test('selectHighestQuality picks the variant with maximum bandwidth', () {
      final variants = [
        const HlsVariant(url: 'https://example.com/360p.m3u8', bandwidth: 800000),
        const HlsVariant(url: 'https://example.com/1080p.m3u8', bandwidth: 5000000),
        const HlsVariant(url: 'https://example.com/720p.m3u8', bandwidth: 2800000),
      ];

      final selected = HlsDownloadService.selectHighestQuality(variants);
      expect(selected.url, equals('https://example.com/1080p.m3u8'));
      expect(selected.bandwidth, equals(5000000));
    });

    test('Custom HlsVariantSelector allows selecting specific variant (e.g. 720p)', () {
      final variants = [
        const HlsVariant(url: 'https://example.com/360p.m3u8', bandwidth: 800000, resolution: '640x360'),
        const HlsVariant(url: 'https://example.com/720p.m3u8', bandwidth: 2800000, resolution: '1280x720'),
        const HlsVariant(url: 'https://example.com/1080p.m3u8', bandwidth: 5000000, resolution: '1920x1080'),
      ];

      // Custom selector prioritizing 720p
      HlsVariant customSelector(List<HlsVariant> list) {
        return list.firstWhere(
          (v) => v.resolution?.contains('720') == true,
          orElse: () => list.first,
        );
      }

      final chosen = customSelector(variants);
      expect(chosen.resolution, equals('1280x720'));
      expect(chosen.url, equals('https://example.com/720p.m3u8'));
    });

    test('parseMediaPlaylist extracts segment URLs and handles relative paths', () {
      const mediaContent = '''#EXTM3U
#EXT-X-VERSION:3
#EXT-X-TARGETDURATION:10
#EXT-X-MEDIA-SEQUENCE:0

#EXTINF:9.009,
segment_0.ts
#EXTINF:9.009,
segment_1.ts
#EXTINF:5.123,
https://cdn-other.example.com/chunks/segment_2.ts
#EXT-X-ENDLIST
''';

      final baseUri = Uri.parse('https://cdn.example.com/media/playlist.m3u8');
      final segments = HlsDownloadService.parseMediaPlaylist(mediaContent, baseUri);

      expect(segments.length, equals(3));
      expect(segments[0], equals('https://cdn.example.com/media/segment_0.ts'));
      expect(segments[1], equals('https://cdn.example.com/media/segment_1.ts'));
      expect(segments[2], equals('https://cdn-other.example.com/chunks/segment_2.ts'));
    });
  });

  group('HlsDownloadService End-to-End Execution Tests', () {
    late Directory tempTestDir;
    late MockFfmpegService mockFfmpeg;
    late Dio testDio;

    setUp(() async {
      tempTestDir = await Directory.systemTemp.createTemp('hls_test_');
      mockFfmpeg = MockFfmpegService();

      testDio = Dio();
      testDio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final path = options.path;
            if (path.endsWith('media.m3u8')) {
              const playlist = '''#EXTM3U
#EXTINF:10.0,
seg0.ts
#EXTINF:10.0,
seg1.ts
#EXT-X-ENDLIST
''';
              return handler.resolve(
                Response(
                  requestOptions: options,
                  data: playlist,
                  statusCode: 200,
                ),
              );
            } else if (path.endsWith('.ts')) {
              // Return mock TS bytes
              return handler.resolve(
                Response(
                  requestOptions: options,
                  data: utf8.encode('mock-ts-binary-content'),
                  statusCode: 200,
                ),
              );
            }
            return handler.next(options);
          },
        ),
      );
    });

    tearDown(() async {
      if (await tempTestDir.exists()) {
        await tempTestDir.delete(recursive: true);
      }
    });

    test('Downloads segments and invokes local remux', () async {
      final hlsService = HlsDownloadService(
        dio: testDio,
        ffmpegService: mockFfmpeg,
      );

      final savePath = p.join(tempTestDir.path, 'video.mkv');
      int lastProgressBytes = 0;

      final success = await hlsService.downloadHlsStream(
        m3u8Url: 'https://cdn.example.com/media.m3u8',
        savePath: savePath,
        taskId: 'test-task-123',
        tempDirectory: tempTestDir,
        onProgress: ({
          required int downloadedBytes,
          required int totalBytes,
          required double speedBytesPerSec,
        }) {
          lastProgressBytes = downloadedBytes;
        },
      );

      expect(success, isTrue);
      expect(mockFfmpeg.lastOutputPath, equals(savePath));
      expect(mockFfmpeg.lastConcatListPath, isNotNull);
      expect(lastProgressBytes, greaterThan(0));
    });
  });
}
