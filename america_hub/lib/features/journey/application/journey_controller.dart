import 'package:flutter/foundation.dart';

import '../../../core/state/async_state.dart';
import '../domain/entities/journey.dart';
import '../domain/repositories/journey_repository.dart';

class JourneyController extends ChangeNotifier {
  JourneyController({required JourneyRepository repository}) : _repository = repository;

  final JourneyRepository _repository;

  AsyncState<JourneySnapshot> _journey = const AsyncLoading();
  AsyncState<JourneySnapshot> get journey => _journey;

  AsyncState<List<JourneyBadge>> _badges = const AsyncLoading();
  AsyncState<List<JourneyBadge>> get badges => _badges;

  AsyncState<List<LeaderboardEntry>> _leaderboard = const AsyncLoading();
  AsyncState<List<LeaderboardEntry>> get leaderboard => _leaderboard;

  LeaderboardScope _scope = LeaderboardScope.city;
  LeaderboardScope get scope => _scope;

  Future<void> load() async {
    _journey = const AsyncLoading();
    _badges = const AsyncLoading();
    notifyListeners();
    // The catalogue and the map are independent reads; a failure in one must not
    // blank out the other, which is why they are not awaited together.
    await Future.wait([_loadJourney(), _loadBadges(), loadLeaderboard(_scope)]);
  }

  Future<void> loadLeaderboard(LeaderboardScope scope) async {
    _scope = scope;
    _leaderboard = const AsyncLoading();
    notifyListeners();
    try {
      _leaderboard = AsyncData(await _repository.getLeaderboard(scope: scope));
    } catch (_) {
      _leaderboard = const AsyncFailure('Liderlik tablosu yüklenemedi.');
    }
    notifyListeners();
  }

  Future<void> _loadJourney() async {
    try {
      _journey = AsyncData(await _repository.getJourney());
    } catch (_) {
      _journey = const AsyncFailure('Gurbet Yolculuğu yüklenemedi.');
    }
    notifyListeners();
  }

  Future<void> _loadBadges() async {
    try {
      _badges = AsyncData(await _repository.getBadges());
    } catch (_) {
      _badges = const AsyncFailure('Rozetler yüklenemedi.');
    }
    notifyListeners();
  }
}
