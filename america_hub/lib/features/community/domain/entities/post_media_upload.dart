import 'community_post.dart';

enum MediaUploadStatus { pending, uploading, ready, rejected, failed }

/// Dosya seçiciden bağımsız, hassas dosya yolunu taşımayan medya tanımı.
class PostMediaUpload {
  const PostMediaUpload({required this.localId, required this.type, required this.fileName, required this.mimeType, required this.sizeBytes, this.status = MediaUploadStatus.pending});
  final String localId;
  final PostMediaType type;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final MediaUploadStatus status;
}

/// Yerel URI yalnızca upload işlemi boyunca kullanılır; post/cache içine
/// yazılmaz. Başarılı sonuçta yalnızca uzak medya URL'si saklanır.
class MediaUploadRequest {
  const MediaUploadRequest({required this.media, required this.localUri});
  final PostMediaUpload media;
  final String localUri;
}

class MediaUploadProgress {
  const MediaUploadProgress({required this.localId, required this.status, required this.fraction, this.media, this.errorMessage});
  final String localId;
  final MediaUploadStatus status;
  final double fraction;
  final PostMedia? media;
  final String? errorMessage;
}
