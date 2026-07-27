import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/entities/create_post_draft.dart';
import 'package:america_hub/features/community/domain/entities/post_media_upload.dart';
import 'package:america_hub/features/community/domain/services/media_upload_policy.dart';
import 'package:america_hub/features/community/domain/services/post_access_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ownerId = 'owner';
  const friendId = 'friend';
  const strangerId = 'stranger';

  CommunityPost post({
    PostVisibility visibility = PostVisibility.friendsOnly,
    CommentsPolicy commentsPolicy = CommentsPolicy.friendsOnly,
  }) => CommunityPost(
    id: 'post-1',
    ownerId: ownerId,
    authorName: 'Ahmet',
    location: 'New York, NY',
    timeLabel: 'Şimdi',
    message: 'Merhaba',
    likes: 0,
    comments: 0,
    visibility: visibility,
    commentsPolicy: commentsPolicy,
  );

  group('PostAccessPolicy', () {
    test('arkadaşlara özel post yabancı kullanıcıya görünmez', () {
      expect(PostAccessPolicy.canView(post: post(), viewerId: strangerId, isFriend: false), isFalse);
      expect(PostAccessPolicy.canView(post: post(), viewerId: friendId, isFriend: true), isTrue);
    });

    test('herkese açık yorum, postu görebilen herkese açıktır', () {
      expect(
        PostAccessPolicy.canComment(
          post: post(visibility: PostVisibility.public, commentsPolicy: CommentsPolicy.everyone),
          viewerId: strangerId,
          isFriend: false,
        ),
        isTrue,
      );
    });

    test('yorumlar kapatıldığında sahibi de yorum yapamaz', () {
      expect(
        PostAccessPolicy.canComment(
          post: post(commentsPolicy: CommentsPolicy.disabled),
          viewerId: ownerId,
          isFriend: false,
        ),
        isFalse,
      );
    });

    test('yorum sahibi veya post sahibi yorumu silebilir', () {
      final comment = CommunityComment(
        id: 'comment-1',
        postId: 'post-1',
        authorId: friendId,
        authorName: 'Elif',
        message: 'Merhaba',
        createdAt: DateTime(2026, 7, 22),
      );
      expect(PostAccessPolicy.canDeleteComment(comment: comment, post: post(), viewerId: friendId), isTrue);
      expect(PostAccessPolicy.canDeleteComment(comment: comment, post: post(), viewerId: ownerId), isTrue);
      expect(PostAccessPolicy.canDeleteComment(comment: comment, post: post(), viewerId: strangerId), isFalse);
    });
  });

  group('CreatePostDraft', () {
    test('medyasız ve metinsiz paylaşım geçersizdir', () {
      const draft = CreatePostDraft(
        message: '  ',
        visibility: PostVisibility.public,
        commentsPolicy: CommentsPolicy.everyone,
      );
      expect(draft.isValid, isFalse);
    });

    test('medyalı paylaşım metin olmadan da geçerlidir', () {
      const draft = CreatePostDraft(
        message: '',
        visibility: PostVisibility.friendsOnly,
        commentsPolicy: CommentsPolicy.friendsOnly,
        media: [PostMedia(id: 'media-1', type: PostMediaType.image, url: 'https://example.com/image.jpg')],
      );
      expect(draft.isValid, isTrue);
    });
  });

  group('MediaUploadPolicy', () {
    test('izinli boyuttaki JPEG görseli kabul eder', () {
      const media = PostMediaUpload(
        localId: 'media-1',
        type: PostMediaType.image,
        fileName: 'piknik.jpg',
        mimeType: 'image/jpeg',
        sizeBytes: 1024,
      );
      expect(MediaUploadPolicy.validate(media), isNull);
    });

    test('izin verilmeyen MIME türünü reddeder', () {
      const media = PostMediaUpload(
        localId: 'media-2',
        type: PostMediaType.image,
        fileName: 'dosya.svg',
        mimeType: 'image/svg+xml',
        sizeBytes: 1024,
      );
      expect(MediaUploadPolicy.validate(media), isNotNull);
    });
  });
}
