import 'package:america_hub/features/auth/data/repositories/mock_auth_repository.dart';
import 'package:america_hub/features/auth/domain/entities/onboarding_draft.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_repository.dart';
import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/entities/create_post_draft.dart';
import 'package:america_hub/features/home/data/community_home_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// "Günün Topluluk Nabzı" sahte servislerle boş kalıyordu: özeti verecek sunucu
/// yok, istek 401 dönüyor, sayaç satırı hiç çizilmiyordu. Artık sayılar
/// uygulamanın kendi verisinden geliyor — ve uydurulmuyor.
void main() {
  late MockAuthRepository auth;
  late MockCommunityRepository community;
  late MockCommunityHomeRepository repository;

  setUp(() async {
    auth = MockAuthRepository();
    await auth.signIn(
      email: MockAuthRepository.demoEmail,
      password: MockAuthRepository.demoPassword,
    );
    community = MockCommunityRepository();
    repository = MockCommunityHomeRepository(
      feed: community,
      stories: community,
      onboarding: auth.getOnboarding,
      viewerId: () => community.viewerId,
    );
  });

  test('the locality comes from what the member answered during setup', () async {
    await auth.saveOnboarding(
      const OnboardingDraft(
        city: 'Paterson',
        regionCode: 'NJ',
        interests: ['yeni-gelen'],
        primaryIntent: 'yeni-gelen',
      ),
    );

    final summary = await repository.fetch();

    expect(summary.city, 'Paterson');
    expect(summary.regionCode, 'NJ');
  });

  test('the counters count what is actually there', () async {
    final summary = await repository.fetch();

    // Akıştaki dört paylaşımın hiçbiri üyenin kendisine ait değil.
    expect(summary.localPosts, 4);
    // Üç demo Story'nin üçü de süresi dolmamış.
    expect(summary.activeStories, 3);
    expect(summary.isNewMember, isTrue);
  });

  test('the member\'s own post does not count as one from around them', () async {
    await community.createPost(
      const CreatePostDraft(
        message: 'Paterson\'da hafta sonu piknik var.',
        visibility: PostVisibility.public,
        commentsPolicy: CommentsPolicy.friendsOnly,
      ),
    );

    final summary = await repository.fetch();

    expect(summary.localPosts, 4);
    expect(summary.isNewMember, isFalse);
  });

  // Arkadaşlık kayıtları Faz 3'te geliyor. O gelene kadar sayacın sıfır
  // durması, olmayan bir çevre göstermekten iyidir.
  test('the connection counter stays at zero until friendships exist', () async {
    expect((await repository.fetch()).connections, 0);
  });
}
