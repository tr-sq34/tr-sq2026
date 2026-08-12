import '../../domain/entities/journey.dart';
import '../../domain/repositories/journey_repository.dart';

/// Offline stand-in for the journey service.
///
/// The shape mirrors `016_member_journey.sql` — the same stages, the same task
/// codes, the same tier points — so the screen built against this behaves the
/// same way against the real catalogue. Only a slice of the 48 badges is here;
/// it exists to make the screen buildable without a backend, not to be a second
/// copy of the catalogue.
class MockJourneyRepository implements JourneyRepository {
  const MockJourneyRepository();

  @override
  Future<JourneySnapshot> getJourney() async => const JourneySnapshot(
    points: 50,
    level: 2,
    levelTitle: 'Local Explorer',
    badgeCount: 1,
    streakDays: 2,
    streakBest: 4,
    nextLevel: 3,
    nextLevelTitle: 'Yeni Komşu',
    nextLevelPoints: 141,
    nextTask: JourneyTask(
      code: 'introduce_self',
      title: 'Kimliğini Tanıt',
      description: 'Profiline fotoğraf ve kısa bir tanıtım ekle.',
      points: 100,
      badgeCode: 'profile_champion',
    ),
    stages: [
      JourneyStage(
        ordinal: 1,
        title: 'Ayağının Tozuyla',
        levelTitle: 'Fresh off the Boat',
        reward: 'Kutlama + 1 hafta çerçeve özelleştirme',
        tasks: [
          JourneyTask(
            code: 'map_pin',
            title: 'Haritaya İğne Koy',
            description: 'Yaşadığın şehri seç.',
            points: 50,
            badgeCode: 'jfk_welcomed',
            completed: true,
          ),
          JourneyTask(
            code: 'introduce_self',
            title: 'Kimliğini Tanıt',
            description: 'Profiline fotoğraf ve kısa bir tanıtım ekle.',
            points: 100,
            badgeCode: 'profile_champion',
          ),
          JourneyTask(
            code: 'first_hello',
            title: 'İlk Selam',
            description: 'İlk paylaşımını yap.',
            points: 150,
            badgeCode: 'welcome_neighbor',
          ),
        ],
      ),
      JourneyStage(
        ordinal: 2,
        title: 'Çevreyi Keşif',
        levelTitle: 'Local Explorer',
        reward: '"Yerel Rehber" unvanı + 1 ücretsiz öne çıkarma',
        tasks: [
          JourneyTask(
            code: 'watchman',
            title: 'Gözcü',
            description: '5 farklı gönderiye etkileşim ver.',
            points: 100,
            badgeCode: 'observer',
            current: 2,
            target: 5,
          ),
        ],
      ),
    ],
  );

  @override
  Future<List<JourneyBadge>> getBadges() async => const [
    JourneyBadge(
      code: 'jfk_welcomed',
      title: 'Ayağının Tozuyla',
      description: 'Profilini oluşturup şehrini seçtin.',
      tier: BadgeTier.bronze,
      category: BadgeCategory.onboarding,
      points: 50,
      earned: true,
      rarityPercent: 82.4,
    ),
    JourneyBadge(
      code: 'observer',
      title: 'Gözcü',
      description: '5 farklı gönderiye etkileşim ver.',
      tier: BadgeTier.bronze,
      category: BadgeCategory.onboarding,
      points: 50,
      current: 2,
      target: 5,
      rarityPercent: 41.0,
    ),
    JourneyBadge(
      code: 'community_beacon',
      title: 'Topluluk Feneri',
      description: 'Bir gönderin 50 beğeni ya da 20 yorum alsın.',
      tier: BadgeTier.silver,
      category: BadgeCategory.social,
      points: 150,
      rarityPercent: 6.2,
    ),
    JourneyBadge(
      code: 'visa_guru',
      title: 'Vize Gurusu',
      description: 'Yanıtın "En Faydalı" seçilsin.',
      tier: BadgeTier.gold,
      category: BadgeCategory.expert,
      points: 500,
      rarityPercent: 1.1,
    ),
    JourneyBadge(
      code: 'turksquare_legend',
      title: 'Turksquare Efsanesi',
      description: '5.000 Gurbet XP topla.',
      tier: BadgeTier.legendary,
      category: BadgeCategory.legendary,
      points: 2000,
      rarityPercent: 0.2,
    ),
    JourneyBadge(
      code: 'night_owl_legend',
      title: 'Gizli rozet',
      description: 'Kriteri açıklanmıyor. Kazandığında burada belirecek.',
      tier: BadgeTier.legendary,
      category: BadgeCategory.secret,
      points: 2000,
      isSecret: true,
      rarityPercent: 0.1,
    ),
  ];

  @override
  Future<List<JourneyBadge>> getBadgesOf(String userId) async =>
      (await getBadges()).where((badge) => badge.earned).toList();

  @override
  Future<List<LeaderboardEntry>> getLeaderboard({
    LeaderboardScope scope = LeaderboardScope.city,
    LeaderboardWindow window = LeaderboardWindow.week,
  }) async => const [
    LeaderboardEntry(userId: 'peer-1', displayName: 'Elif D.', score: 700, level: 5, rank: 1, city: 'Paterson', regionCode: 'NJ'),
    LeaderboardEntry(userId: 'peer-2', displayName: 'Mert K.', score: 350, level: 4, rank: 2, city: 'Paterson', regionCode: 'NJ'),
    // "Sen" rather than a name: the mock has no idea who is signed in, and the
    // one thing a self row must not do is call the member somebody else.
    LeaderboardEntry(userId: 'local-user', displayName: 'Sen', score: 50, level: 2, rank: 3, city: 'Paterson', regionCode: 'NJ', isSelf: true),
  ];
}
