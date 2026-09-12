import '../../core/enums.dart';
import '../../core/utils.dart';

class DownloadTask {
  final String id;
  final String url;
  final String fileName;
  final String savePath;
  final int totalBytes;
  final int downloadedBytes;
  final DownloadStatus status;
  final DownloadCategory category;
  final double speedBytesPerSec;
  final DateTime dateAdded;
  final DateTime? dateCompleted;
  final String? errorMessage;
  final Map<String, String>? headers;
  final bool isResumable;
  final String? fileHash;
  final HashAlgorithm? hashAlgorithm;
  final bool fileMissing;

  const DownloadTask({
    required this.id,
    required this.url,
    required this.fileName,
    required this.savePath,
    this.totalBytes = 0,
    this.downloadedBytes = 0,
    this.status = DownloadStatus.queued,
    this.category = DownloadCategory.other,
    this.speedBytesPerSec = 0.0,
    required this.dateAdded,
    this.dateCompleted,
    this.errorMessage,
    this.headers,
    this.isResumable = true,
    this.fileHash,
    this.hashAlgorithm,
    this.fileMissing = false,
  });

  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  bool get isIndeterminate => totalBytes <= 0 && status == DownloadStatus.downloading;

  String get formattedTotalSize => AppUtils.formatFileSize(totalBytes);
  String get formattedDownloadedSize => AppUtils.formatFileSize(downloadedBytes);
  String get formattedSpeed => AppUtils.formatSpeed(speedBytesPerSec);

  Duration? get eta {
    if (speedBytesPerSec <= 0 || totalBytes <= 0 || downloadedBytes >= totalBytes) {
      return null;
    }
    final remainingBytes = totalBytes - downloadedBytes;
    final seconds = (remainingBytes / speedBytesPerSec).round();
    return Duration(seconds: seconds);
  }

  String get formattedEta {
    final e = eta;
    return e == null ? '--' : AppUtils.formatDuration(e);
  }

  DownloadTask copyWith({
    String? id,
    String? url,
    String? fileName,
    String? savePath,
    int? totalBytes,
    int? downloadedBytes,
    DownloadStatus? status,
    DownloadCategory? category,
    double? speedBytesPerSec,
    DateTime? dateAdded,
    DateTime? dateCompleted,
    String? errorMessage,
    bool clearError = false,
    Map<String, String>? headers,
    bool? isResumable,
    String? fileHash,
    HashAlgorithm? hashAlgorithm,
    bool? fileMissing,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      url: url ?? this.url,
      fileName: fileName ?? this.fileName,
      savePath: savePath ?? this.savePath,
      totalBytes: totalBytes ?? this.totalBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      status: status ?? this.status,
      category: category ?? this.category,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      dateAdded: dateAdded ?? this.dateAdded,
      dateCompleted: dateCompleted ?? this.dateCompleted,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      headers: headers ?? this.headers,
      isResumable: isResumable ?? this.isResumable,
      fileHash: fileHash ?? this.fileHash,
      hashAlgorithm: hashAlgorithm ?? this.hashAlgorithm,
      fileMissing: fileMissing ?? this.fileMissing,
    );
  }
}
