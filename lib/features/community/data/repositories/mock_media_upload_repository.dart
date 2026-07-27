import '../../domain/entities/community_post.dart';
import '../../domain/entities/post_media_upload.dart';
import '../../domain/repositories/media_upload_repository.dart';
import '../../domain/services/media_upload_policy.dart';

/// Backend olmadan geliştirme için. Gerçek implementasyon aynı stream
/// sözleşmesini S3/R2/Firebase veya uygulama API'sine bağlayacaktır.
class MockMediaUploadRepository implements MediaUploadRepository {
  @override
  Stream<MediaUploadProgress> upload(MediaUploadRequest request) async* {
    final validationError = MediaUploadPolicy.validate(request.media);
    if (validationError != null) {
      yield MediaUploadProgress(localId: request.media.localId, status: MediaUploadStatus.rejected, fraction: 0, errorMessage: validationError);
      return;
    }
    yield MediaUploadProgress(localId: request.media.localId, status: MediaUploadStatus.uploading, fraction: .15);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    yield MediaUploadProgress(localId: request.media.localId, status: MediaUploadStatus.uploading, fraction: .65);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    yield MediaUploadProgress(
      localId: request.media.localId,
      status: MediaUploadStatus.ready,
      fraction: 1,
      media: PostMedia(id: request.media.localId, type: request.media.type, url: request.localUri),
    );
  }
}
