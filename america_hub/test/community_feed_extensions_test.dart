import 'package:america_hub/features/community/data/repositories/mock_community_repository.dart';
import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/entities/create_post_draft.dart';
import 'package:america_hub/features/community/domain/entities/feed_extensions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Community feed extensions', () {
    test(
      'single-choice poll rejects multiple choices and persists one vote',
      () async {
        final repository = MockCommunityRepository();
        final post = await repository.createPost(
          CreatePostDraft(
            message: 'Hangi gün?',
            visibility: PostVisibility.public,
            commentsPolicy: CommentsPolicy.everyone,
            poll: const CommunityPoll(
              id: 'poll-1',
              question: 'Hangi gün?',
              selectionMode: PollSelectionMode.single,
              options: [
                PollOption(id: 'sat', label: 'Cumartesi'),
                PollOption(id: 'sun', label: 'Pazar'),
              ],
            ),
          ),
        );
        await expectLater(
          repository.vote(
            postId: post.id,
            pollId: 'poll-1',
            optionIds: {'sat', 'sun'},
          ),
          throwsArgumentError,
        );
        final poll = await repository.vote(
          postId: post.id,
          pollId: 'poll-1',
          optionIds: {'sat'},
        );
        expect(poll.selectedOptionIds, {'sat'});
        expect(poll.options.first.votes, 1);
      },
    );

    // With an empty rail there was nothing to tap, so the whole story feature
    // read as broken in mock mode. These three exist only in this repository.
    test('mock mode has stories to walk through', () async {
      final page = await MockCommunityRepository().fetchStories();

      expect(page.items, hasLength(3));
      expect(page.items.every((story) => !story.isExpired), isTrue);
      expect(page.items.map((story) => story.authorName), contains('Elif Demir'));
    });

    test('viewing and liking a demo story sticks', () async {
      final repository = MockCommunityRepository();
      final first = (await repository.fetchStories()).items.first;

      final viewed = await repository.markViewed(first.id);
      final liked = await repository.setLiked(first.id, true);

      expect(viewed.isViewed, isTrue);
      expect(liked.likeCount, first.likeCount + 1);
      expect((await repository.fetchStories()).items.first.isViewed, isTrue);
    });

    test('story TTL accepts supported durations only', () {
      final media = PostMedia(
        id: 'media',
        type: PostMediaType.image,
        url: 'https://cdn.example.com/photo.jpg',
      );
      expect(
        CreateStoryDraft(
          media: media,
          visibility: StoryVisibility.network,
          ttl: const Duration(hours: 12),
        ).validationError,
        isNull,
      );
      expect(
        CreateStoryDraft(
          media: media,
          visibility: StoryVisibility.network,
          ttl: const Duration(hours: 8),
        ).validationError,
        isNotNull,
      );
    });
  });
}
