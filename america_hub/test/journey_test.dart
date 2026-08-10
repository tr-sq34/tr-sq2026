import 'package:america_hub/features/journey/application/journey_controller.dart';
import 'package:america_hub/features/journey/data/repositories/mock_journey_repository.dart';
import 'package:america_hub/features/journey/domain/entities/journey.dart';
import 'package:america_hub/features/journey/domain/repositories/journey_repository.dart';
import 'package:america_hub/features/journey/presentation/screens/journey_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A catalogue that fails only on the leaderboard, to prove one broken read
/// does not blank the other two.
class _PartlyBrokenRepository implements JourneyRepository {
  const _PartlyBrokenRepository();

  @override
  Future<JourneySnapshot> getJourney() => const MockJourneyRepository().getJourney();

  @override
  Future<List<JourneyBadge>> getBadges() => const MockJourneyRepository().getBadges();

  @override
  Future<List<JourneyBadge>> getBadgesOf(String userId) async => const [];

  @override
  Future<List<LeaderboardEntry>> getLeaderboard({
    LeaderboardScope scope = LeaderboardScope.city,
    LeaderboardWindow window = LeaderboardWindow.week,
  }) async => throw StateError('down');
}

Future<void> _pumpJourney(WidgetTester tester, JourneyRepository repository) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: JourneyScreen(controller: JourneyController(repository: repository)),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  group('progress arithmetic', () {
    test('the level bar measures points against the next threshold', () {
      const snapshot = JourneySnapshot(
        points: 50,
        level: 2,
        levelTitle: 'Local Explorer',
        badgeCount: 1,
        streakDays: 2,
        streakBest: 4,
        nextLevelPoints: 100,
        stages: [],
      );

      expect(snapshot.progress, 0.5);
    });

    test('the top of the ladder reads as complete rather than dividing by zero', () {
      const snapshot = JourneySnapshot(
        points: 17150,
        level: 50,
        levelTitle: 'Gurbet Efsanesi',
        badgeCount: 40,
        streakDays: 0,
        streakBest: 30,
        stages: [],
      );

      expect(snapshot.progress, 1);
    });

    test('an earned badge is full even when it never had a counter', () {
      const badge = JourneyBadge(
        code: 'first_spark',
        title: 'İlk Kıvılcım',
        description: 'İlk story',
        tier: BadgeTier.bronze,
        category: BadgeCategory.onboarding,
        earned: true,
      );

      expect(badge.progress, 1);
      expect(badge.hasProgress, isFalse);
    });

    test('a stage is only complete when every task in it is', () {
      const stage = JourneyStage(
        ordinal: 1,
        title: 'Ayağının Tozuyla',
        levelTitle: 'Fresh off the Boat',
        reward: 'kutlama',
        tasks: [
          JourneyTask(code: 'a', title: 'A', description: '', points: 50, badgeCode: 'a', completed: true),
          JourneyTask(code: 'b', title: 'B', description: '', points: 50, badgeCode: 'b'),
        ],
      );

      expect(stage.doneCount, 1);
      expect(stage.completed, isFalse);
    });
  });

  testWidgets('the badge cabinet separates earned, in progress and locked', (tester) async {
    await _pumpJourney(tester, const MockJourneyRepository());

    await tester.tap(find.widgetWithText(Tab, 'Rozetler'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('Kazanılanlar · 1'), findsOneWidget);
    expect(find.text('Devam edenler · 1'), findsOneWidget);
    expect(find.text('Kilitli · 4'), findsOneWidget);
  });

  testWidgets('a secret badge keeps its criteria to itself', (tester) async {
    await _pumpJourney(tester, const MockJourneyRepository());

    await tester.tap(find.widgetWithText(Tab, 'Rozetler'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('Gizli rozet'), findsOneWidget);
    expect(find.textContaining('02:00'), findsNothing);
  });

  testWidgets('a broken leaderboard does not take the task map down with it', (tester) async {
    await _pumpJourney(tester, const _PartlyBrokenRepository());

    expect(find.text('Ayağının Tozuyla'), findsNothing);
    expect(find.text('1. Ayağının Tozuyla'), findsOneWidget);

    await tester.tap(find.widgetWithText(Tab, 'Liderlik'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('Liderlik tablosu yüklenemedi.'), findsOneWidget);
  });
}
