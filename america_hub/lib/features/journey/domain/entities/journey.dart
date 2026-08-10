import '../../../profile/domain/entities/user_profile.dart' show BadgeTier, badgeTierFrom;

export '../../../profile/domain/entities/user_profile.dart' show BadgeTier, badgeTierFrom;

enum BadgeCategory { onboarding, social, expert, legendary, secret }

BadgeCategory badgeCategoryFrom(String? raw) => switch (raw) {
  'social' => BadgeCategory.social,
  'expert' => BadgeCategory.expert,
  'legendary' => BadgeCategory.legendary,
  'secret' => BadgeCategory.secret,
  _ => BadgeCategory.onboarding,
};

/// A catalogue entry seen through one member's eyes.
///
/// A secret badge that has not been earned arrives from the server without its
/// real title or criteria — there is nothing to hide client-side, because the
/// answer was never sent.
class JourneyBadge {
  const JourneyBadge({
    required this.code,
    required this.title,
    required this.description,
    required this.tier,
    required this.category,
    this.icon = 'star',
    this.points = 0,
    this.isSecret = false,
    this.earned = false,
    this.earnedAt,
    this.current = 0,
    this.target,
    this.rarityPercent = 0,
  });

  final String code;
  final String title;
  final String description;
  final BadgeTier tier;
  final BadgeCategory category;
  final String icon;
  final int points;
  final bool isSecret;
  final bool earned;
  final DateTime? earnedAt;
  final int current;
  final int? target;

  /// "Üyelerin %3'ü aldı" — the number that turns a badge into something worth
  /// racing for.
  final double rarityPercent;

  bool get hasProgress => !earned && (target ?? 0) > 1;
  double get progress {
    final total = target ?? 0;
    if (total <= 0) return earned ? 1 : 0;
    return (current / total).clamp(0.0, 1.0);
  }

  factory JourneyBadge.fromJson(Map<String, dynamic> json) => JourneyBadge(
    code: json['code'] as String,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    tier: badgeTierFrom(json['tier'] as String?),
    category: badgeCategoryFrom(json['category'] as String?),
    icon: json['icon'] as String? ?? 'star',
    points: (json['points'] as num?)?.toInt() ?? 0,
    isSecret: json['isSecret'] as bool? ?? false,
    earned: json['earned'] as bool? ?? false,
    earnedAt: DateTime.tryParse(json['earnedAt'] as String? ?? ''),
    current: (json['current'] as num?)?.toInt() ?? 0,
    target: (json['target'] as num?)?.toInt(),
    rarityPercent: (json['rarityPercent'] as num?)?.toDouble() ?? 0,
  );
}

class JourneyTask {
  const JourneyTask({
    required this.code,
    required this.title,
    required this.description,
    required this.points,
    required this.badgeCode,
    this.completed = false,
    this.current = 0,
    this.target = 1,
  });

  final String code;
  final String title;
  final String description;
  final int points;
  final String badgeCode;
  final bool completed;
  final int current;
  final int target;

  double get progress => target <= 0 ? 0 : (current / target).clamp(0.0, 1.0);

  factory JourneyTask.fromJson(Map<String, dynamic> json) => JourneyTask(
    code: json['code'] as String,
    title: json['title'] as String? ?? '',
    description: json['description'] as String? ?? '',
    points: (json['points'] as num?)?.toInt() ?? 0,
    badgeCode: json['badgeCode'] as String? ?? '',
    completed: json['completed'] as bool? ?? false,
    current: (json['current'] as num?)?.toInt() ?? 0,
    target: (json['target'] as num?)?.toInt() ?? 1,
  );
}

class JourneyStage {
  const JourneyStage({
    required this.ordinal,
    required this.title,
    required this.levelTitle,
    required this.reward,
    required this.tasks,
  });

  final int ordinal;
  final String title;
  final String levelTitle;
  final String reward;
  final List<JourneyTask> tasks;

  bool get completed => tasks.isNotEmpty && tasks.every((task) => task.completed);
  int get doneCount => tasks.where((task) => task.completed).length;

  factory JourneyStage.fromJson(Map<String, dynamic> json) => JourneyStage(
    ordinal: (json['ordinal'] as num?)?.toInt() ?? 0,
    title: json['title'] as String? ?? '',
    levelTitle: json['levelTitle'] as String? ?? '',
    reward: json['reward'] as String? ?? '',
    tasks: (json['tasks'] as List<dynamic>? ?? const [])
        .map((task) => JourneyTask.fromJson(task as Map<String, dynamic>))
        .toList(),
  );
}

class JourneySnapshot {
  const JourneySnapshot({
    required this.points,
    required this.level,
    required this.levelTitle,
    required this.badgeCount,
    required this.streakDays,
    required this.streakBest,
    required this.stages,
    this.nextLevel,
    this.nextLevelTitle,
    this.nextLevelPoints,
    this.nextTask,
    this.perksFrozenUntil,
  });

  final int points;
  final int level;
  final String levelTitle;
  final int badgeCount;
  final int streakDays;
  final int streakBest;
  final List<JourneyStage> stages;
  final int? nextLevel;
  final String? nextLevelTitle;
  final int? nextLevelPoints;
  final JourneyTask? nextTask;

  /// Set while VIP perks are suspended for inactivity or a moderation warning.
  /// The screen says so plainly rather than silently dropping the perk row.
  final DateTime? perksFrozenUntil;

  double get progress {
    final next = nextLevelPoints;
    if (next == null || next <= 0) return 1;
    return (points / next).clamp(0.0, 1.0);
  }

  factory JourneySnapshot.fromJson(Map<String, dynamic> json) => JourneySnapshot(
    points: (json['points'] as num?)?.toInt() ?? 0,
    level: (json['level'] as num?)?.toInt() ?? 1,
    levelTitle: json['levelTitle'] as String? ?? 'Fresh off the Boat',
    badgeCount: (json['badgeCount'] as num?)?.toInt() ?? 0,
    streakDays: (json['streakDays'] as num?)?.toInt() ?? 0,
    streakBest: (json['streakBest'] as num?)?.toInt() ?? 0,
    nextLevel: (json['nextLevel'] as num?)?.toInt(),
    nextLevelTitle: json['nextLevelTitle'] as String?,
    nextLevelPoints: (json['nextLevelPoints'] as num?)?.toInt(),
    perksFrozenUntil: DateTime.tryParse(json['perksFrozenUntil'] as String? ?? ''),
    nextTask: json['nextTask'] is Map<String, dynamic>
        ? JourneyTask.fromJson(json['nextTask'] as Map<String, dynamic>)
        : null,
    stages: (json['stages'] as List<dynamic>? ?? const [])
        .map((stage) => JourneyStage.fromJson(stage as Map<String, dynamic>))
        .toList(),
  );
}

enum LeaderboardScope { city, region, global }

enum LeaderboardWindow { week, all }

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.userId,
    required this.displayName,
    required this.score,
    required this.level,
    required this.rank,
    this.city,
    this.regionCode,
    this.isSelf = false,
  });

  final String userId;
  final String displayName;
  final int score;
  final int level;
  final int rank;
  final String? city;
  final String? regionCode;
  final bool isSelf;

  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) => LeaderboardEntry(
    userId: json['userId'] as String? ?? '',
    displayName: json['displayName'] as String? ?? 'TurkSquare üyesi',
    score: (json['score'] as num?)?.toInt() ?? 0,
    level: (json['level'] as num?)?.toInt() ?? 1,
    rank: (json['rank'] as num?)?.toInt() ?? 0,
    city: json['city'] as String?,
    regionCode: json['regionCode'] as String?,
    isSelf: json['isSelf'] as bool? ?? false,
  );
}
