import 'dart:io';
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
}

