import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/network/api_exception.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/auth/data/repositories/mock_auth_repository.dart';
import 'package:america_hub/features/auth/domain/entities/onboarding_draft.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_repository.dart';
import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/entities/create_post_draft.dart';
import 'package:america_hub/features/home/application/community_home_controller.dart';
import 'package:america_hub/features/home/data/community_home_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/recording_adapter.dart';
import 'support/shell_harness.dart';

ApiCommunityHomeRepository apiRepository(Object? body, {int statusCode = 200}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://community.test/v1/'))
    ..httpClientAdapter = RecordingAdapter(body, statusCode: statusCode);
  return ApiCommunityHomeRepository(
    ApiClient(tokenStore: InMemoryTokenStore(), dio: dio),
  );
}

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

  // Sunucu 401 dediğinde ekranda "0 Bağlantın · 0 Çevrende paylaşım · 0 Aktif
  // Story" yazıyordu. Sunucu sayı vermedi, "seni tanımıyorum" dedi; ikisi aynı
  // şey değil ve üyeye sıfır göstermek sessizce yanlış bilgi vermekti.
  test('an unauthenticated summary does not turn into zeros', () async {
    final controller = CommunityHomeController(
      apiRepository(
        {'error': {'code': 'HOME_SUMMARY_UNAVAILABLE', 'message': 'Ana sayfa özeti yüklenemedi.'}},
        statusCode: 401,
      ),
    );

    await controller.load();

    expect(controller.summary, isNull);
    expect(controller.error, contains('yeniden giriş'));
  });

  test('a body without `data` is a failure, not a summary full of zeros', () async {
    await expectLater(
      apiRepository(const <String, dynamic>{}).fetch(),
      throwsA(isA<ApiException>()),
    );
  });

  testWidgets('the home screen says the pulse could not be read', (tester) async {
    await pumpShell(tester, homeRepository: _FailingHomeRepository());
    await tester.pump();

    expect(find.textContaining('Topluluk nabzı yüklenemedi'), findsOneWidget);
    expect(find.text('Yeniden dene'), findsOneWidget);
    // Gelmeyen sayının yerine hiçbir şey yazılmıyor.
    expect(find.text('Bağlantın'), findsNothing);
  });
}

class _FailingHomeRepository implements CommunityHomeRepository {
  @override
  Future<CommunityHomeSummary> fetch() async =>
      throw const ApiException(message: 'Sunucuya ulaşılamadı.', statusCode: 503);
}
