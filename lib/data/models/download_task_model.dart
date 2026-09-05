import '../../core/enums.dart';
import '../../domain/models/download_task.dart';

class DownloadTaskModel {
  static Map<String, dynamic> toJson(DownloadTask task) {
    return {
      'id': task.id,
      'url': task.url,
      'fileName': task.fileName,
      'savePath': task.savePath,
      'totalBytes': task.totalBytes,
      'downloadedBytes': task.downloadedBytes,
      // If task was downloading or queued when app closed, persist as paused
      'status': (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued)
          ? DownloadStatus.paused.name
          : task.status.name,
      'category': task.category.name,
      'dateAdded': task.dateAdded.toIso8601String(),
      'dateCompleted': task.dateCompleted?.toIso8601String(),
      'errorMessage': task.errorMessage,
    };
  }

  static DownloadTask fromJson(Map<String, dynamic> json) {
    final statusName = json['status'] as String? ?? 'paused';
    final status = DownloadStatus.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => DownloadStatus.paused,
    );

    final categoryName = json['category'] as String? ?? 'other';
    final category = DownloadCategory.values.firstWhere(
      (e) => e.name == categoryName,
      orElse: () => DownloadCategory.other,
    );

    return DownloadTask(
      id: json['id'] as String,
      url: json['url'] as String,
      fileName: json['fileName'] as String,
      savePath: json['savePath'] as String,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      status: status,
      category: category,
      speedBytesPerSec: 0.0,
      dateAdded: DateTime.tryParse(json['dateAdded'] as String? ?? '') ?? DateTime.now(),
      dateCompleted: json['dateCompleted'] != null
          ? DateTime.tryParse(json['dateCompleted'] as String)
          : null,
      errorMessage: json['errorMessage'] as String?,
    );
  }
}

