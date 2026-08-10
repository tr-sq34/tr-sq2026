import '../entities/journey.dart';

abstract interface class JourneyRepository {
  Future<JourneySnapshot> getJourney();
  Future<List<JourneyBadge>> getBadges();
  Future<List<JourneyBadge>> getBadgesOf(String userId);
  Future<List<LeaderboardEntry>> getLeaderboard({
    LeaderboardScope scope = LeaderboardScope.city,
    LeaderboardWindow window = LeaderboardWindow.week,
  });
}
