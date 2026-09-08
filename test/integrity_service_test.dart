import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:virusdownloader/core/enums.dart';
import 'package:virusdownloader/data/services/integrity_service.dart';

void main() {
  group('IntegrityService & Hashing Tests', () {
    late IntegrityService integrityService;
    late Directory tempDir;
    late File testFile;

    setUp(() async {
      integrityService = IntegrityService();
      tempDir = await Directory.systemTemp.createTemp('vd_integrity_test_');
      testFile = File('${tempDir.path}/sample.txt');
      await testFile.writeAsString('Hello VirusDownloader! 12345');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('Computes MD5 hash correctly', () async {
      final hash = await integrityService.calculateFileHash(
        testFile.path,
        HashAlgorithm.md5,
      );
      expect(hash, isNotEmpty);
      expect(hash.length, 32);
    });

    test('Computes SHA1 hash correctly', () async {
      final hash = await integrityService.calculateFileHash(
        testFile.path,
        HashAlgorithm.sha1,
      );
      expect(hash, isNotEmpty);
      expect(hash.length, 40);
    });

    test('Computes SHA256 hash correctly', () async {
      final hash = await integrityService.calculateFileHash(
        testFile.path,
        HashAlgorithm.sha256,
      );
      expect(hash, isNotEmpty);
      expect(hash.length, 64);
    });

    test('Computes SHA512 hash correctly', () async {
      final hash = await integrityService.calculateFileHash(
        testFile.path,
        HashAlgorithm.sha512,
      );
      expect(hash, isNotEmpty);
      expect(hash.length, 128);
    });

    test('Computes CRC32 checksum correctly', () async {
      final hash = await integrityService.calculateFileHash(
        testFile.path,
        HashAlgorithm.crc32,
      );
      expect(hash, isNotEmpty);
      expect(hash.length, 8);
    });

    test('compareHashes verifies match regardless of whitespace or case', () {
      const h1 = 'A1B2C3D4E5F6';
      const h2 = '  a1b2c3d4e5f6  ';
      const h3 = 'a1b2c3d4e5f7';

      expect(integrityService.compareHashes(h1, h2), isTrue);
      expect(integrityService.compareHashes(h1, h3), isFalse);
      expect(integrityService.compareHashes('', h1), isFalse);
    });
  });

  group('IntegrityService Zero-Piece Detection & In-Place Repair Tests', () {
    late IntegrityService integrityService;
    late Directory tempDir;

    setUp(() async {
      integrityService = IntegrityService();
      tempDir = await Directory.systemTemp.createTemp('vd_zero_repair_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('findZeroPieces returns empty list on non-existent or empty files', () async {
      final emptyFile = File('${tempDir.path}/empty.bin');
      await emptyFile.create();

      final nonExistent = await integrityService.findZeroPieces('${tempDir.path}/missing.bin');
      final fromEmpty = await integrityService.findZeroPieces(emptyFile.path);

      expect(nonExistent, isEmpty);
      expect(fromEmpty, isEmpty);
    });

    test('findZeroPieces correctly identifies all-zero pieces and skips non-zero pieces', () async {
      final testFile = File('${tempDir.path}/chunked.bin');
      // Create a 3000-byte file:
      // Piece 0 (0..999): filled with 0xFF (non-zero)
      // Piece 1 (1000..1999): filled with 0x00 (all zeros - missing gap)
      // Piece 2 (2000..2999): filled with 0xAA (non-zero)
      final bytes = Uint8List(3000);
      bytes.fillRange(0, 1000, 0xFF);
      bytes.fillRange(1000, 2000, 0x00);
      bytes.fillRange(2000, 3000, 0xAA);
      await testFile.writeAsBytes(bytes);

      final pieces = await integrityService.findZeroPieces(testFile.path, pieceSize: 1000);

      expect(pieces.length, 1);
      expect(pieces[0].index, 1);
      expect(pieces[0].startByte, 1000);
      expect(pieces[0].endByte, 1999);
      expect(pieces[0].length, 1000);
    });

    test('findZeroPieces identifies all pieces if whole pre-allocated file is zero', () async {
      final testFile = File('${tempDir.path}/all_zeros.bin');
      final bytes = Uint8List(2500); // 3 pieces with pieceSize 1000: [0..999], [1000..1999], [2000..2499]
      await testFile.writeAsBytes(bytes);

      final pieces = await integrityService.findZeroPieces(testFile.path, pieceSize: 1000);

      expect(pieces.length, 3);
      expect(pieces[0].index, 0);
      expect(pieces[0].startByte, 0);
      expect(pieces[0].endByte, 999);

      expect(pieces[1].index, 1);
      expect(pieces[1].startByte, 1000);
      expect(pieces[1].endByte, 1999);

      expect(pieces[2].index, 2);
      expect(pieces[2].startByte, 2000);
      expect(pieces[2].endByte, 2499);
      expect(pieces[2].length, 500);
    });

    test('findZeroPieces returns empty when no zero pieces exist', () async {
      final testFile = File('${tempDir.path}/full_data.bin');
      final bytes = Uint8List(2000);
      for (int i = 0; i < bytes.length; i++) {
        bytes[i] = (i % 250) + 1; // 1..250 (no zeros)
      }
      await testFile.writeAsBytes(bytes);

      final pieces = await integrityService.findZeroPieces(testFile.path, pieceSize: 500);
      expect(pieces, isEmpty);
    });

    test('repairZeroPieces patches missing piece in-place without corrupting surrounding data', () async {
      final testFile = File('${tempDir.path}/to_repair.bin');
      // 3000 bytes: [0..999]=0x11, [1000..1999]=0x00, [2000..2999]=0x22
      final initialBytes = Uint8List(3000);
      initialBytes.fillRange(0, 1000, 0x11);
      initialBytes.fillRange(1000, 2000, 0x00);
      initialBytes.fillRange(2000, 3000, 0x22);
      await testFile.writeAsBytes(initialBytes);

      // Setup mock Dio interceptor serving range requests
      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final rangeHeader = options.headers['range'] as String?;
          if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
            final parts = rangeHeader.substring(6).split('-');
            final start = int.parse(parts[0]);
            final end = int.parse(parts[1]);
            final len = end - start + 1;
            // Return dummy repaired content (0x77)
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 206,
              data: Uint8List(len)..fillRange(0, len, 0x77),
            ));
          }
          return handler.resolve(Response(
            requestOptions: options,
            statusCode: 200,
            data: <int>[],
          ));
        },
      ));

      final piecesToRepair = [
        ZeroPiece(index: 1, startByte: 1000, endByte: 1999),
      ];

      final result = await integrityService.repairZeroPieces(
        url: 'https://example.com/file.bin',
        localFilePath: testFile.path,
        pieces: piecesToRepair,
        dio: dio,
      );

      expect(result.isSuccess, isTrue);
      expect(result.totalPieces, 1);
      expect(result.repairedPieces, 1);
      expect(result.failedPieces, 0);

      // Verify file contents:
      final readBytes = await testFile.readAsBytes();
      expect(readBytes.length, 3000);
      // Piece 0 untouched
      expect(readBytes.sublist(0, 1000), everyElement(0x11));
      // Piece 1 patched with 0x77
      expect(readBytes.sublist(1000, 2000), everyElement(0x77));
      // Piece 2 untouched
      expect(readBytes.sublist(2000, 3000), everyElement(0x22));

      // Re-scan should now show 0 zero pieces
      final afterScan = await integrityService.findZeroPieces(testFile.path, pieceSize: 1000);
      expect(afterScan, isEmpty);
    });

    test('scanAndRepairZeroGaps performs full end-to-end scan and in-place patch', () async {
      final testFile = File('${tempDir.path}/full_flow.bin');
      final initialBytes = Uint8List(2000);
      initialBytes.fillRange(0, 1000, 0x33);
      initialBytes.fillRange(1000, 2000, 0x00); // piece 1 is gap
      await testFile.writeAsBytes(initialBytes);

      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          final rangeHeader = options.headers['range'] as String?;
          if (rangeHeader != null && rangeHeader.startsWith('bytes=')) {
            final parts = rangeHeader.substring(6).split('-');
            final start = int.parse(parts[0]);
            final end = int.parse(parts[1]);
            final len = end - start + 1;
            return handler.resolve(Response(
              requestOptions: options,
              statusCode: 206,
              data: Uint8List(len)..fillRange(0, len, 0x88),
            ));
          }
          return handler.reject(DioException(requestOptions: options));
        },
      ));

      final result = await integrityService.scanAndRepairZeroGaps(
        url: 'https://example.com/stream.bin',
        localFilePath: testFile.path,
        dio: dio,
        pieceSize: 1000,
      );

      expect(result.isSuccess, isTrue);
      expect(result.totalPieces, 1);
      expect(result.repairedPieces, 1);

      // Verify second scan finds nothing to repair
      final secondResult = await integrityService.scanAndRepairZeroGaps(
        url: 'https://example.com/stream.bin',
        localFilePath: testFile.path,
        dio: dio,
        pieceSize: 1000,
      );
      expect(secondResult.isSuccess, isTrue);
      expect(secondResult.totalPieces, 0);
      expect(secondResult.repairedPieces, 0);
    });

    test('repairZeroPieces handles failed requests gracefully', () async {
      final testFile = File('${tempDir.path}/fail_repair.bin');
      await testFile.writeAsBytes(Uint8List(1000));

      final dio = Dio();
      dio.interceptors.add(InterceptorsWrapper(
        onRequest: (options, handler) {
          return handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
              error: 'Connection refused',
            ),
          );
        },
      ));

      final result = await integrityService.repairZeroPieces(
        url: 'https://badserver.local/file.bin',
        localFilePath: testFile.path,
        pieces: [ZeroPiece(index: 0, startByte: 0, endByte: 999)],
        dio: dio,
        maxRetriesPerPiece: 1, // fast failure for unit test
      );

      expect(result.isSuccess, isFalse);
      expect(result.repairedPieces, 0);
      expect(result.failedPieces, 1);
    });
  });
}


