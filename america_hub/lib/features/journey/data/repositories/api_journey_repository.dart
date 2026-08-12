import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/entities/journey.dart';
import '../../domain/repositories/journey_repository.dart';

class ApiJourneyRepository implements JourneyRepository {
  ApiJourneyRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<JourneySnapshot> getJourney() async {
    final response = await _client.get<Map<String, dynamic>>(ApiEndpoints.communityJourney);
    return JourneySnapshot.fromJson(response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<List<JourneyBadge>> getBadges() => _badges(ApiEndpoints.communityBadges);

  @override
  Future<List<JourneyBadge>> getBadgesOf(String userId) =>
      _badges(ApiEndpoints.communityUserBadges(userId));

  @override
  Future<List<LeaderboardEntry>> getLeaderboard({
    LeaderboardScope scope = LeaderboardScope.city,
    LeaderboardWindow window = LeaderboardWindow.week,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityLeaderboard,
      queryParameters: {'scope': scope.name, 'window': window.name},
    );
    return (response.data!['data'] as List<dynamic>)
        .map((raw) => LeaderboardEntry.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  Future<List<JourneyBadge>> _badges(String path) async {
    final response = await _client.get<Map<String, dynamic>>(path);
    return (response.data!['data'] as List<dynamic>)
        .map((raw) => JourneyBadge.fromJson(raw as Map<String, dynamic>))
        .toList();
  }
}
