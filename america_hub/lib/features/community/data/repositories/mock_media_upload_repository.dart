import '../../domain/entities/community_post.dart';
import '../../domain/entities/post_media_upload.dart';
import '../../domain/repositories/media_upload_repository.dart';
import '../../domain/services/media_upload_policy.dart';

/// Backend olmadan geliştirme için. Gerçek implementasyon aynı stream
/// sözleşmesini S3/R2/Firebase veya uygulama API'sine bağlayacaktır.
class MockMediaUploadRepository implements MediaUploadRepository {
  /// Medya kimliği → yerel dosya yolu. Sunucudaki `media_assets` tablosunun
  /// yerini tutar: yükleme bir kimlik üretir, o kimliği bir adrese çeviren tek
  /// yer burasıdır. Kimliği adres sanıp doğrudan `Image.network`'e vermek
  /// avatarın hiç görünmemesine yol açıyordu.
  final Map<String, String> _assets = {};

  /// Yükleme kimliğinin işaret ettiği yerel dosya yolu; bilinmiyorsa null.
  String? resolve(String mediaId) => _assets[mediaId];

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
    _assets[request.media.localId] = request.localUri;
    yield MediaUploadProgress(
      localId: request.media.localId,
      status: MediaUploadStatus.ready,
      fraction: 1,
      media: PostMedia(id: request.media.localId, type: request.media.type, url: request.localUri),
    );
  }
}
