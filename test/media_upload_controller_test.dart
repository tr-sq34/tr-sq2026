import 'package:america_hub/features/community/application/media_upload_controller.dart';
import 'package:america_hub/features/community/data/repositories/mock_media_upload_repository.dart';
import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/entities/post_media_upload.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('geçerli medya upload sonunda hazır medya olarak görünür', () async {
    final controller = MediaUploadController(repository: MockMediaUploadRepository());
    const request = MediaUploadRequest(
      localUri: 'file:///piknik.jpg',
      media: PostMediaUpload(
        localId: 'local-1',
        type: PostMediaType.image,
        fileName: 'piknik.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
      ),
    );

    await controller.upload(request);

    expect(controller.hasPendingUploads, isFalse);
    expect(controller.readyMedia, hasLength(1));
  });
}
