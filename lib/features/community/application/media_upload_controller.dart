import 'package:flutter/foundation.dart';

import '../domain/entities/community_post.dart';
import '../domain/entities/post_media_upload.dart';
import '../domain/repositories/media_upload_repository.dart';

class MediaUploadController extends ChangeNotifier {
  MediaUploadController({required MediaUploadRepository repository}) : _repository = repository;
  final MediaUploadRepository _repository;
  final Map<String, MediaUploadProgress> _progressById = {};
  final Map<String, MediaUploadRequest> _requestsById = {};
  Map<String, MediaUploadProgress> get progressById => Map.unmodifiable(_progressById);

  bool get hasPendingUploads => _progressById.values.any((item) => item.status == MediaUploadStatus.pending || item.status == MediaUploadStatus.uploading);
  List<PostMedia> get readyMedia => _progressById.values.map((item) => item.media).whereType<PostMedia>().toList(growable: false);

  Future<void> upload(MediaUploadRequest request) async {
    _requestsById[request.media.localId] = request;
    try {
      await for (final progress in _repository.upload(request)) {
        _progressById[progress.localId] = progress;
        notifyListeners();
      }
    } catch (_) {
      _progressById[request.media.localId] = MediaUploadProgress(
        localId: request.media.localId,
        status: MediaUploadStatus.failed,
        fraction: 0,
        errorMessage: 'Medya yüklenemedi.',
      );
      notifyListeners();
    }
  }

  Future<void> retry(String localId) {
    final request = _requestsById[localId];
    if (request == null) return Future<void>.value();
    return upload(request);
  }

  void remove(String localId) {
    _progressById.remove(localId);
    _requestsById.remove(localId);
    notifyListeners();
  }

  void clear() {
    _progressById.clear();
    _requestsById.clear();
    notifyListeners();
  }
}
