import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../core/enums.dart';
import '../../core/utils.dart';

class Crc32 {
  static final List<int> _table = _buildTable();

  static List<int> _buildTable() {
    final table = List<int>.filled(256, 0);
    for (int i = 0; i < 256; i++) {
      int c = i;
      for (int j = 0; j < 8; j++) {
        if ((c & 1) != 0) {
          c = 0xEDB88320 ^ (c >>> 1);
        } else {
          c = c >>> 1;
        }
      }
      table[i] = c;
    }
    return table;
  }

  int _crc = 0xFFFFFFFF;

  void add(List<int> chunk) {
    for (int i = 0; i < chunk.length; i++) {
      _crc = _table[(_crc ^ chunk[i]) & 0xFF] ^ (_crc >>> 8);
    }
  }

  int close() {
    return (_crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}

class RecheckResult {
  final bool isVerified;
  final int verifiedBytes;
  final int totalBytes;
  final String message;
  final int? corruptByteOffset;

  const RecheckResult({
    required this.isVerified,
    required this.verifiedBytes,
    required this.totalBytes,
    required this.message,
    this.corruptByteOffset,
  });
}

class ZeroPiece {
  final int index;
  final int startByte;
  final int endByte;

  const ZeroPiece({
    required this.index,
    required this.startByte,
    required this.endByte,
  });

  int get length => (endByte - startByte) + 1;

  @override
  String toString() => 'ZeroPiece(idx: $index, range: $startByte-$endByte, len: $length)';
}

class RepairResult {
  final bool isSuccess;
  final int totalPieces;
  final int repairedPieces;
  final int failedPieces;
  final String message;

  const RepairResult({
    required this.isSuccess,
    required this.totalPieces,
    required this.repairedPieces,
    required this.failedPieces,
    required this.message,
  });
}

class IntegrityService {
  /// Calculate cryptographic or checksum hash of a local file
  Future<String> calculateFileHash(
    String filePath,
    HashAlgorithm algorithm, {
    void Function(double progress)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', filePath);
    }

    final totalBytes = await file.length();
    if (totalBytes == 0) {
      return _emptyHash(algorithm);
    }

    final stream = file.openRead();
    int readBytes = 0;

    switch (algorithm) {
      case HashAlgorithm.md5:
        Digest? digest;
        final sink = md5.startChunkedConversion(ChunkedConversionSink<Digest>.withCallback((accumulated) {
          if (accumulated.isNotEmpty) digest = accumulated.single;
        }));
        await for (final chunk in stream) {
          if (cancelToken?.isCancelled ?? false) break;
          sink.add(chunk);
          readBytes += chunk.length;
          onProgress?.call(readBytes / totalBytes);
        }
        sink.close();
        return digest?.toString() ?? '';

      case HashAlgorithm.sha1:
        Digest? digest;
        final sink = sha1.startChunkedConversion(ChunkedConversionSink<Digest>.withCallback((accumulated) {
          if (accumulated.isNotEmpty) digest = accumulated.single;
        }));
        await for (final chunk in stream) {
          if (cancelToken?.isCancelled ?? false) break;
          sink.add(chunk);
          readBytes += chunk.length;
          onProgress?.call(readBytes / totalBytes);
        }
        sink.close();
        return digest?.toString() ?? '';

      case HashAlgorithm.sha256:
        Digest? digest;
        final sink = sha256.startChunkedConversion(ChunkedConversionSink<Digest>.withCallback((accumulated) {
          if (accumulated.isNotEmpty) digest = accumulated.single;
        }));
        await for (final chunk in stream) {
          if (cancelToken?.isCancelled ?? false) break;
          sink.add(chunk);
          readBytes += chunk.length;
          onProgress?.call(readBytes / totalBytes);
        }
        sink.close();
        return digest?.toString() ?? '';

      case HashAlgorithm.sha512:
        Digest? digest;
        final sink = sha512.startChunkedConversion(ChunkedConversionSink<Digest>.withCallback((accumulated) {
          if (accumulated.isNotEmpty) digest = accumulated.single;
        }));
        await for (final chunk in stream) {
          if (cancelToken?.isCancelled ?? false) break;
          sink.add(chunk);
          readBytes += chunk.length;
          onProgress?.call(readBytes / totalBytes);
        }
        sink.close();
        return digest?.toString() ?? '';

      case HashAlgorithm.crc32:
        final crc = Crc32();
        await for (final chunk in stream) {
          if (cancelToken?.isCancelled ?? false) break;
          crc.add(chunk);
          readBytes += chunk.length;
          onProgress?.call(readBytes / totalBytes);
        }
        final result = crc.close();
        return result.toRadixString(16).padLeft(8, '0');
    }
  }

  String _emptyHash(HashAlgorithm algorithm) {
    switch (algorithm) {
      case HashAlgorithm.md5:
        return md5.convert([]).toString();
      case HashAlgorithm.sha1:
        return sha1.convert([]).toString();
      case HashAlgorithm.sha256:
        return sha256.convert([]).toString();
      case HashAlgorithm.sha512:
        return sha512.convert([]).toString();
      case HashAlgorithm.crc32:
        return '00000000';
    }
  }

  /// Compares two hash strings, ignoring whitespace and case
  bool compareHashes(String hash1, String hash2) {
    final h1 = hash1.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    final h2 = hash2.replaceAll(RegExp(r'\s+'), '').toLowerCase();
    if (h1.isEmpty || h2.isEmpty) return false;
    return h1 == h2;
  }

  /// Rechecks a file against remote server using Range sampling (torrent-style recheck).
  /// Verifies file size and probes multiple strategic segments (head, mid, tail, and step samples).
  Future<RecheckResult> recheckFile({
    required String url,
    required String localFilePath,
    required Dio dio,
    Map<String, String>? headers,
    void Function(double progress, String status)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      return const RecheckResult(
        isVerified: false,
        verifiedBytes: 0,
        totalBytes: 0,
        message: 'Local file does not exist on disk.',
      );
    }

    final localLength = await file.length();
    if (localLength == 0) {
      return const RecheckResult(
        isVerified: false,
        verifiedBytes: 0,
        totalBytes: 0,
        message: 'Local file is empty (0 bytes).',
      );
    }

    onProgress?.call(0.05, 'Probing remote server headers...');

    // 1. Probe remote server
    final reqHeaders = <String, dynamic>{'range': 'bytes=0-0'};
    if (headers != null) reqHeaders.addAll(headers);

    Response resp;
    try {
      resp = await dio.head(
        url,
        options: Options(
          headers: reqHeaders,
          validateStatus: (status) => status != null && status >= 200 && status < 400,
        ),
        cancelToken: cancelToken,
      );
    } catch (e) {
      return RecheckResult(
        isVerified: false,
        verifiedBytes: 0,
        totalBytes: localLength,
        message: 'Failed to contact server: $e',
      );
    }

    final acceptRanges = resp.headers.value(HttpHeaders.acceptRangesHeader)?.toLowerCase();
    final contentRange = resp.headers.value(HttpHeaders.contentRangeHeader);
    int remoteTotal = 0;

    if (contentRange != null) {
      final match = RegExp(r'/(\d+)').firstMatch(contentRange);
      if (match != null) {
        remoteTotal = int.tryParse(match.group(1) ?? '') ?? 0;
      }
    } else {
      final cl = resp.headers.value(HttpHeaders.contentLengthHeader);
      if (cl != null) remoteTotal = int.tryParse(cl) ?? 0;
    }

    final isResumable = resp.statusCode == 206 ||
        acceptRanges == 'bytes' ||
        contentRange != null;

    if (!isResumable) {
      return RecheckResult(
        isVerified: false,
        verifiedBytes: 0,
        totalBytes: localLength,
        message: 'Server does not support resumable / byte-range downloads. Cannot recheck.',
      );
    }

    if (remoteTotal > 0 && localLength != remoteTotal) {
      return RecheckResult(
        isVerified: false,
        verifiedBytes: localLength,
        totalBytes: remoteTotal,
        message: 'File size mismatch: local is $localLength bytes, remote is $remoteTotal bytes.',
      );
    }

    final targetTotal = remoteTotal > 0 ? remoteTotal : localLength;

    // 2. Sample checks at start, 25%, 50%, 75%, and end of file (up to 256 KB each)
    const sampleSize = 256 * 1024;
    final checkOffsets = <int>{
      0,
      if (targetTotal > sampleSize * 4) (targetTotal * 0.25).toInt(),
      if (targetTotal > sampleSize * 2) (targetTotal * 0.50).toInt(),
      if (targetTotal > sampleSize * 4) (targetTotal * 0.75).toInt(),
      if (targetTotal > sampleSize) (targetTotal - sampleSize),
    }.toList()..sort();

    final raf = await file.open(mode: FileMode.read);
    try {
      for (int i = 0; i < checkOffsets.length; i++) {
        if (cancelToken?.isCancelled ?? false) break;

        final offset = checkOffsets[i];
        final bytesToCheck = (targetTotal - offset).clamp(1, sampleSize);
        final progress = (i + 1) / (checkOffsets.length + 1);

        onProgress?.call(
          progress,
          'Verifying block at ${AppUtils.formatFileSize(offset)}...',
        );

        // Fetch remote bytes
        final sampleHeaders = <String, dynamic>{
          'range': 'bytes=$offset-${offset + bytesToCheck - 1}',
        };
        if (headers != null) sampleHeaders.addAll(headers);

        final sampleResp = await dio.get<List<int>>(
          url,
          options: Options(
            responseType: ResponseType.bytes,
            headers: sampleHeaders,
            validateStatus: (s) => s != null && s >= 200 && s < 400,
          ),
          cancelToken: cancelToken,
        );

        final remoteBytes = sampleResp.data;
        if (remoteBytes == null || remoteBytes.length != bytesToCheck) {
          return RecheckResult(
            isVerified: false,
            verifiedBytes: offset,
            totalBytes: targetTotal,
            message: 'Incomplete data received from server for block at offset $offset.',
            corruptByteOffset: offset,
          );
        }

        // Read local bytes
        await raf.setPosition(offset);
        final localBytes = await raf.read(bytesToCheck);

        if (!listEquals(localBytes, remoteBytes)) {
          return RecheckResult(
            isVerified: false,
            verifiedBytes: offset,
            totalBytes: targetTotal,
            message: 'Byte mismatch detected at offset ${AppUtils.formatFileSize(offset)}.',
            corruptByteOffset: offset,
          );
        }
      }
    } finally {
      await raf.close();
    }

    onProgress?.call(1.0, 'Integrity recheck complete.');
    return RecheckResult(
      isVerified: true,
      verifiedBytes: targetTotal,
      totalBytes: targetTotal,
      message: 'File integrity verified successfully against remote server.',
    );
  }

  /// Scans a local file piece-by-piece to find missing/unwritten zero-filled blocks
  /// (typical in pre-allocated placeholder files where segments were interrupted).
  ///
  /// Uses ultra-fast checking: as soon as any byte in a block is non-zero,
  /// the piece is skipped immediately.
  Future<List<ZeroPiece>> findZeroPieces(
    String filePath, {
    int pieceSize = 8 * 1024 * 1024, // 8 MB default piece size
    void Function(double progress, String status)? onProgress,
    CancelToken? cancelToken,
  }) async {
    final file = File(filePath);
    if (!await file.exists()) return [];

    final totalSize = await file.length();
    if (totalSize == 0) return [];

    final numPieces = (totalSize + pieceSize - 1) ~/ pieceSize;
    final zeroPieces = <ZeroPiece>[];
    const scanReadSize = 4 * 1024 * 1024; // 4 MB read granularity

    final raf = await file.open(mode: FileMode.read);
    try {
      for (int idx = 0; idx < numPieces; idx++) {
        if (cancelToken?.isCancelled ?? false) break;

        final start = idx * pieceSize;
        final end = math.min((idx + 1) * pieceSize - 1, totalSize - 1);
        final length = (end - start) + 1;

        onProgress?.call(
          idx / numPieces,
          'Scanning for missing pieces: ${idx + 1}/$numPieces (${AppUtils.formatFileSize(start)})...',
        );

        await raf.setPosition(start);
        bool isZero = true;
        int remaining = length;

        while (remaining > 0) {
          final readLen = math.min(scanReadSize, remaining);
          final buffer = await raf.read(readLen);
          if (buffer.isEmpty) {
            break;
          }

          // Ultra-fast zero check: exit on first non-zero byte
          for (int i = 0; i < buffer.length; i++) {
            if (buffer[i] != 0) {
              isZero = false;
              break;
            }
          }

          if (!isZero) break;
          remaining -= readLen;
        }

        if (isZero) {
          zeroPieces.add(ZeroPiece(index: idx, startByte: start, endByte: end));
        }
      }
    } finally {
      await raf.close();
    }

    onProgress?.call(1.0, 'Scan complete. Found ${zeroPieces.length} missing piece(s).');
    return zeroPieces;
  }

  /// Re-downloads only the specified zero pieces using HTTP Range requests
  /// and writes them directly into the file in-place at the exact offset.
  Future<RepairResult> repairZeroPieces({
    required String url,
    required String localFilePath,
    required List<ZeroPiece> pieces,
    required Dio dio,
    Map<String, String>? headers,
    void Function(double progress, String status)? onProgress,
    CancelToken? cancelToken,
    int maxRetriesPerPiece = 5,
  }) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      return const RepairResult(
        isSuccess: false,
        totalPieces: 0,
        repairedPieces: 0,
        failedPieces: 0,
        message: 'File does not exist on disk.',
      );
    }

    if (pieces.isEmpty) {
      return const RepairResult(
        isSuccess: true,
        totalPieces: 0,
        repairedPieces: 0,
        failedPieces: 0,
        message: 'No missing pieces to repair.',
      );
    }

    int repairedCount = 0;
    final failedPieces = <ZeroPiece>[];

    // Open file in append/write mode to allow random seeking and in-place writes
    final raf = await file.open(mode: FileMode.append);

    try {
      for (int i = 0; i < pieces.length; i++) {
        if (cancelToken?.isCancelled ?? false) break;

        final piece = pieces[i];
        final pieceProg = i / pieces.length;
        onProgress?.call(
          pieceProg,
          'Patching piece ${i + 1}/${pieces.length} (${AppUtils.formatFileSize(piece.startByte)} - ${AppUtils.formatFileSize(piece.endByte)})...',
        );

        final reqHeaders = <String, dynamic>{
          'range': 'bytes=${piece.startByte}-${piece.endByte}',
        };
        if (headers != null) reqHeaders.addAll(headers);

        List<int>? pieceData;
        int backoffSeconds = 2;

        for (int attempt = 1; attempt <= maxRetriesPerPiece; attempt++) {
          if (cancelToken?.isCancelled ?? false) break;
          try {
            final resp = await dio.get<List<int>>(
              url,
              options: Options(
                responseType: ResponseType.bytes,
                headers: reqHeaders,
                validateStatus: (s) => s != null && s >= 200 && s < 400,
              ),
              cancelToken: cancelToken,
            );

            if (resp.statusCode == 429) {
              await Future.delayed(Duration(seconds: backoffSeconds));
              backoffSeconds = math.min(backoffSeconds * 2, 30);
              continue;
            }

            final data = resp.data;
            if (data != null && data.length == piece.length) {
              pieceData = data;
              break;
            } else {
              await Future.delayed(Duration(seconds: backoffSeconds));
              backoffSeconds = math.min(backoffSeconds * 2, 30);
            }
          } catch (e) {
            await Future.delayed(Duration(seconds: backoffSeconds));
            backoffSeconds = math.min(backoffSeconds * 2, 30);
          }
        }

        if (pieceData != null) {
          await raf.setPosition(piece.startByte);
          await raf.writeFrom(pieceData);
          await raf.flush();
          repairedCount++;
        } else {
          failedPieces.add(piece);
        }
      }
    } finally {
      await raf.close();
    }

    final isSuccess = failedPieces.isEmpty;
    onProgress?.call(
      1.0,
      isSuccess
          ? 'Successfully repaired all $repairedCount piece(s)!'
          : 'Repaired $repairedCount piece(s), ${failedPieces.length} failed.',
    );

    return RepairResult(
      isSuccess: isSuccess,
      totalPieces: pieces.length,
      repairedPieces: repairedCount,
      failedPieces: failedPieces.length,
      message: isSuccess
          ? 'Successfully patched all $repairedCount missing piece(s).'
          : 'Repaired $repairedCount piece(s), ${failedPieces.length} piece(s) failed.',
    );
  }

  /// Scans for all-zero gaps and immediately re-downloads & patches them in-place.
  Future<RepairResult> scanAndRepairZeroGaps({
    required String url,
    required String localFilePath,
    required Dio dio,
    int pieceSize = 8 * 1024 * 1024,
    Map<String, String>? headers,
    void Function(double progress, String status)? onProgress,
    CancelToken? cancelToken,
  }) async {
    onProgress?.call(0.0, 'Scanning file for missing zero-filled gaps...');
    final zeroPieces = await findZeroPieces(
      localFilePath,
      pieceSize: pieceSize,
      onProgress: (prog, status) => onProgress?.call(prog * 0.4, status),
      cancelToken: cancelToken,
    );

    if (zeroPieces.isEmpty) {
      onProgress?.call(1.0, 'No missing zero-filled pieces found. File appears complete.');
      return const RepairResult(
        isSuccess: true,
        totalPieces: 0,
        repairedPieces: 0,
        failedPieces: 0,
        message: 'No missing zero-filled pieces found.',
      );
    }

    onProgress?.call(
      0.4,
      'Found ${zeroPieces.length} missing piece(s). Beginning in-place patch...',
    );

    return await repairZeroPieces(
      url: url,
      localFilePath: localFilePath,
      pieces: zeroPieces,
      dio: dio,
      headers: headers,
      onProgress: (prog, status) => onProgress?.call(0.4 + prog * 0.6, status),
      cancelToken: cancelToken,
    );
  }
}
