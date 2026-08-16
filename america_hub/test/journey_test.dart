import 'package:america_hub/features/journey/application/journey_controller.dart';
import 'package:america_hub/features/journey/data/repositories/mock_journey_repository.dart';
import 'package:america_hub/features/journey/domain/entities/journey.dart';
import 'package:america_hub/features/journey/domain/entities/journey_action.dart';
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

/// Yalnızca "gün atlamadan gir" görevini taşıyan bir harita: bu görevin
/// açılacak bir ekranı yok.
class _StreakOnlyRepository implements JourneyRepository {
  const _StreakOnlyRepository();

  @override
  Future<JourneySnapshot> getJourney() async => const JourneySnapshot(
    points: 300,
    level: 3,
    levelTitle: 'Permanent Resident',
    badgeCount: 2,
    streakDays: 1,
    streakBest: 4,
    stages: [
      JourneyStage(
        ordinal: 3,
        title: 'Gurbetçi Alışkanlığı',
        levelTitle: 'Permanent Resident',
        reward: 'Gümüş rozet slotu',
        tasks: [
          JourneyTask(
            code: 'loyalty_chain',
            title: 'Sadakat Zinciri',
            description: 'Üç gün aralıksız uygulamaya gir.',
            points: 300,
            badgeCode: 'first_spark',
          ),
        ],
      ),
    ],
  );

  @override
  Future<List<JourneyBadge>> getBadges() async => const [];

  @override
  Future<List<JourneyBadge>> getBadgesOf(String userId) async => const [];

  @override
  Future<List<LeaderboardEntry>> getLeaderboard({
    LeaderboardScope scope = LeaderboardScope.city,
    LeaderboardWindow window = LeaderboardWindow.week,
  }) async => const [];
}

Future<void> _pumpJourney(
  WidgetTester tester,
  JourneyRepository repository, {
  JourneyTab initialTab = JourneyTab.tasks,
  void Function(JourneyDestination destination)? onTaskAction,
  // Rozet sekmesi seviye şeridiyle başlayıp kilitli grupla bitiyor; kaydırma
  // koreografisi testin konusu değil, o yüzden yüzey uzun tutuluyor.
  double viewHeight = 2400,
}) async {
  tester.view.physicalSize = Size(1080, viewHeight);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: JourneyScreen(
        controller: JourneyController(repository: repository),
        initialTab: initialTab,
        onTaskAction: onTaskAction,
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Sekme geçişi ile açılır grubun animasyonu üst üste biniyor; kısa bir bekleme
/// hâlâ hareket hâlindeki bir satıra dokunmak demek oluyordu.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.pump(const Duration(milliseconds: 100));
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
    await _pumpJourney(tester, const MockJourneyRepository(), viewHeight: 4800);

    await tester.tap(find.widgetWithText(Tab, 'Rozetler'));
    await _settle(tester);

    expect(find.text('Kazanılanlar · 1'), findsOneWidget);
    expect(find.text('Devam edenler · 1'), findsOneWidget);
    expect(find.text('Kilitli · 4'), findsOneWidget);
  });

  testWidgets('a badge entry point opens on the badge tab, not on the tasks', (tester) async {
    // The profile's Rozet counter and the home screen's badge card both come
    // in this way; landing on Görevler made them look like dead links.
    await _pumpJourney(
      tester,
      const MockJourneyRepository(),
      initialTab: JourneyTab.badges,
    );

    expect(find.text('Kazanılanlar · 1'), findsOneWidget);
  });

  testWidgets('a secret badge keeps its criteria to itself', (tester) async {
    await _pumpJourney(tester, const MockJourneyRepository(), viewHeight: 4800);

    await tester.tap(find.widgetWithText(Tab, 'Rozetler'));
    await _settle(tester);
    // Kilitli grup kapalı açılıyor: kırk küsur satır kazanılan rozetleri
    // ekranın dışına itiyordu.
    await tester.tap(find.text('Kilitli · 4'));
    await _settle(tester);

    expect(find.text('Gizli rozet'), findsOneWidget);
    expect(find.textContaining('02:00'), findsNothing);
  });

  testWidgets('the badge tab says where the member stands and what is next', (
    tester,
  ) async {
    // Kafa karışıklığı buydu: rozet sayacından gelen üye kırk sekiz rozetin
    // arasında seviyesini de sıradaki işi de bulamıyordu.
    await _pumpJourney(
      tester,
      const MockJourneyRepository(),
      initialTab: JourneyTab.badges,
      viewHeight: 4800,
    );

    expect(find.text('Sv.2 Local Explorer'), findsOneWidget);
    expect(find.textContaining('91 XP kaldı'), findsOneWidget);
    expect(find.text('Sıradaki adımın'), findsOneWidget);
    // Bitmiş görev sıraya girmiyor, bitmemişlerin ilk üçü giriyor.
    expect(find.text('Haritaya İğne Koy'), findsNothing);
    expect(find.text('Kimliğini Tanıt'), findsOneWidget);
  });

  testWidgets('a task hands the member to the screen that finishes it', (
    tester,
  ) async {
    final opened = <JourneyDestination>[];
    await _pumpJourney(
      tester,
      const MockJourneyRepository(),
      onTaskAction: opened.add,
    );

    await tester.tap(find.text('İlk Selam'));
    await _settle(tester);

    expect(opened, [JourneyDestination.composer]);
  });

  testWidgets('a finished task is not a button any more', (tester) async {
    final opened = <JourneyDestination>[];
    await _pumpJourney(
      tester,
      const MockJourneyRepository(),
      onTaskAction: opened.add,
    );

    // "Haritaya İğne Koy" bitmiş: dokunmak konum ekranını açmamalı.
    await tester.tap(find.text('Haritaya İğne Koy'));
    await _settle(tester);

    expect(opened, isEmpty);
  });

  testWidgets('a task with nowhere to go does not pretend to be a link', (
    tester,
  ) async {
    final opened = <JourneyDestination>[];
    await _pumpJourney(tester, const _StreakOnlyRepository(), onTaskAction: opened.add);

    // "Üç gün araliksız gir" görevi bir ekranda yapılmıyor; satırın ne eylem
    // etiketi var ne de dokunulduğunda bir yere gidiyor.
    expect(find.text('Sadakat Zinciri'), findsOneWidget);
    expect(find.text('Akışa git'), findsNothing);
    await tester.tap(find.text('Sadakat Zinciri'));
    await _settle(tester);

    expect(opened, isEmpty);
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
