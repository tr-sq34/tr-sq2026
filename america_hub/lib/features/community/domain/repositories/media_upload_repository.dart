import '../entities/community_post.dart';
import '../entities/post_media_upload.dart';

abstract interface class MediaUploadRepository {
  /// Emits progress; the final ready state always contains a durable media URL.
  Stream<MediaUploadProgress> upload(MediaUploadRequest request);
}
