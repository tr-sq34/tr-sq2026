import '../../../core/network/api_client.dart';
import '../../auth/domain/entities/onboarding_profile.dart';
import '../../community/domain/repositories/community_repository.dart';

class CommunityHomeSummary {
  const CommunityHomeSummary({
    required this.city,
    required this.regionCode,
    required this.connections,
    required this.localPosts,
    required this.activeStories,
    required this.isNewMember,
  });
  final String? city;
  final String? regionCode;
  final int connections;
  final int localPosts;
  final int activeStories;
  final bool isNewMember;

  factory CommunityHomeSummary.fromJson(Map<String, dynamic> json) {
    final locality = json['locality'] as Map<String, dynamic>?;
    final counts = json['counts'] as Map<String, dynamic>? ?? const {};
    int count(String key) => (counts[key] as num?)?.toInt() ?? 0;
    return CommunityHomeSummary(
      city: locality?['city'] as String?,
      regionCode: locality?['regionCode'] as String?,
      connections: count('connections'),
      localPosts: count('localPosts'),
      activeStories: count('activeStories'),
      isNewMember: json['isNewMember'] == true,
    );
  }
}

abstract interface class CommunityHomeRepository {
  Future<CommunityHomeSummary> fetch();
}

class ApiCommunityHomeRepository implements CommunityHomeRepository {
  ApiCommunityHomeRepository(this._client);
  final ApiClient _client;

  @override
  Future<CommunityHomeSummary> fetch() async {
    final response = await _client.get<Map<String, dynamic>>(
      '/community/home/summary',
    );
    final payload = response.data?['data'] as Map<String, dynamic>? ?? const {};
    return CommunityHomeSummary.fromJson(payload);
  }
}

/// Sahte servislerle çalışırken özeti sunacak bir sunucu yok: istek 401 dönüyor,
/// nabız satırı hiç çizilmiyor ve üst bardaki şehir satırı boş kalıyordu. Buradaki
/// sayılar uydurulmuyor — akışta gerçekten duran paylaşımlar, süresi dolmamış
/// Story'ler ve üyenin kurulumda yazdığı şehir sayılıyor.
class MockCommunityHomeRepository implements CommunityHomeRepository {
  MockCommunityHomeRepository({
    required CommunityRepository feed,
    required StoryRepository stories,
    required Future<OnboardingProfile> Function() onboarding,
    required String Function() viewerId,
  }) : _feed = feed,
       _stories = stories,
       _onboarding = onboarding,
       _viewerId = viewerId;

  final CommunityRepository _feed;
  final StoryRepository _stories;
  final Future<OnboardingProfile> Function() _onboarding;
  final String Function() _viewerId;

  @override
  Future<CommunityHomeSummary> fetch() async {
    final profile = await _onboarding();
    final posts = await _feed.getFeed();
    final stories = (await _stories.fetchStories(limit: 100)).items;
    final now = DateTime.now();
    final viewer = _viewerId();
    return CommunityHomeSummary(
      city: profile.city,
      regionCode: profile.regionCode,
      // Arkadaşlık kayıtları Faz 3'te geliyor; o gelene kadar sayaç sıfır
      // duruyor — burada bir sayı üretmek üyeye olmayan bir çevre göstermek olur.
      connections: 0,
      localPosts: posts.where((post) => post.ownerId != viewer).length,
      activeStories: stories.where((story) => story.expiresAt.isAfter(now)).length,
      isNewMember: posts.every((post) => post.ownerId != viewer),
    );
  }
}
