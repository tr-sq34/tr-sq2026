import '../entities/community_post.dart';
import '../entities/post_media_upload.dart';

abstract final class MediaUploadPolicy {
  static const _imageTypes = {'image/jpeg', 'image/png', 'image/webp'};
  static const _videoTypes = {'video/mp4', 'video/quicktime'};
  static const maxImageBytes = 10 * 1024 * 1024;
  static const maxVideoBytes = 100 * 1024 * 1024;

  static String? validate(PostMediaUpload media) {
    final allowedTypes = media.type == PostMediaType.image ? _imageTypes : _videoTypes;
    if (!allowedTypes.contains(media.mimeType.toLowerCase())) return 'Bu medya türü desteklenmiyor.';
    final maxBytes = media.type == PostMediaType.image ? maxImageBytes : maxVideoBytes;
    if (media.sizeBytes <= 0 || media.sizeBytes > maxBytes) return 'Medya dosyası izin verilen boyutu aşıyor.';
    return null;
  }
}
