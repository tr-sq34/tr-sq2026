enum ProfileVisibility { public, friendsOnly }

/// Bronz → Elmas. The tier decides the frame a badge is drawn in, so it is an
/// enum rather than a colour the server sends: a backend that starts emitting
/// "platinum" should fail loudly here, not paint an invisible badge.
enum BadgeTier { bronze, silver, gold, legendary }

BadgeTier badgeTierFrom(String? raw) => switch (raw) {
  'silver' => BadgeTier.silver,
  'gold' => BadgeTier.gold,
  'legendary' => BadgeTier.legendary,
  _ => BadgeTier.bronze,
};

/// A badge as it appears on a profile card — just enough to draw the chip.
/// The full catalogue entry (criteria, progress, rarity) lives in the journey
/// feature; the profile only ever shows the three the member chose to display.
class ProfileBadge {
  const ProfileBadge({
    required this.code,
    required this.title,
    this.icon = 'star',
    this.tier = BadgeTier.bronze,
  });

  final String code;
  final String title;
  final String icon;
  final BadgeTier tier;
}

/// The Gurbet Yolculuğu line on the profile card: where the member is and what
/// is next. The full map is fetched separately when they open the journey.
class JourneySummary {
  const JourneySummary({
    this.points = 0,
    this.level = 1,
    this.levelTitle = 'Fresh off the Boat',
    this.nextLevelPoints,
    this.streakDays = 0,
  });

  final int points;
  final int level;
  final String levelTitle;
  final int? nextLevelPoints;
  final int streakDays;

  /// How far along the current level the member is, 0..1. Returns 1 at the top
  /// of the curve, where there is no next threshold to divide by.
  double get progress {
    final next = nextLevelPoints;
    if (next == null || next <= 0) return 1;
    return (points / next).clamp(0.0, 1.0);
  }
}

/// Takipçi ya da takip edilen listesindeki tek satır.
class FollowSummary {
  const FollowSummary({
    required this.userId,
    required this.displayName,
    this.username,
    this.city,
    this.regionCode,
    this.avatarUrl,
    this.viewerFollows = false,
  });

  final String userId;
  final String displayName;
  final String? username;
  final String? city;
  final String? regionCode;
  final String? avatarUrl;

  /// Bakan kişinin bu üyeyi takip edip etmediği. Listedeki düğmenin "Takip et"
  /// mi "Takiptesin" mi yazacağını bu belirliyor.
  final bool viewerFollows;

  String get placeLabel =>
      [city, regionCode].where((part) => (part ?? '').isNotEmpty).join(', ');

  FollowSummary copyWith({bool? viewerFollows}) => FollowSummary(
    userId: userId,
    displayName: displayName,
    username: username,
    city: city,
    regionCode: regionCode,
    avatarUrl: avatarUrl,
    viewerFollows: viewerFollows ?? this.viewerFollows,
  );
}

/// Kullanıcı adı denetiminin cevabı. "Müsait değil" tek başına yeterli değil:
/// kuralı çiğnediği için mi yoksa alındığı için mi reddedildiğini bilmeyen üye
/// aynı adı bir daha dener.
class UsernameCheck {
  const UsernameCheck({required this.available, required this.message});

  final bool available;
  final String message;
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.email,
    this.username,
    this.city,
    this.state,
    this.interests = const [],
    this.avatarUrl,
    this.visibility = ProfileVisibility.friendsOnly,
    this.isOnboardingComplete = false,
    this.bio = '',
    this.originCity,
    this.originCountry,
    this.bornInUs = false,
    this.arrivedMonth,
    this.arrivedYear,
    this.primaryIntent,
    this.identityVerified = false,
    this.showcasedBadges = const [],
    this.journey = const JourneySummary(),
    this.postCount = 0,
    this.friendCount = 0,
    this.followerCount = 0,
    this.followingCount = 0,
    this.badgeCount = 0,
    this.viewerFollows = false,
    this.followsViewer = false,
    this.isSelf = true,
    this.canViewFullProfile = true,
  });

  final String id;
  final String displayName;
  final String email;

  /// `@` olmadan saklanıyor, `@` ile gösteriliyor. Üye henüz seçmediyse null:
  /// görünen addan türetilmiş bir tanıtıcı uydurmak, kimsenin sahiplenmediği
  /// bir adı profile yazmak olurdu.
  final String? username;
  final String? city;
  final String? state;
  final List<String> interests;
  final String? avatarUrl;
  final ProfileVisibility visibility;
  final bool isOnboardingComplete;
  final String bio;

  /// Where the member came from. Owned by identity (the onboarding answers),
  /// projected into community — so it is read here and edited through
  /// `PUT /v1/auth/onboarding`, never written back through the profile PATCH.
  final String? originCity;
  final String? originCountry;
  final bool bornInUs;
  final int? arrivedMonth;
  final int? arrivedYear;
  final String? primaryIntent;

  final bool identityVerified;
  final List<ProfileBadge> showcasedBadges;
  final JourneySummary journey;
  final int postCount;
  final int friendCount;

  /// Takip tek yönlü, arkadaşlık çift yönlü. Arkadaşlık kabul edildiğinde iki
  /// yönlü satır yazıldığı için her arkadaş aynı zamanda hem takipçi hem takip
  /// edilen sayılıyor; iki sayaç bu yüzden arkadaş sayısından küçük olamaz.
  final int followerCount;
  final int followingCount;
  final int badgeCount;

  /// Bakan kişi ile bu profil arasındaki takip ilişkisi. Kendi profilinde
  /// ikisi de false: kimse kendini takip etmiyor.
  final bool viewerFollows;
  final bool followsViewer;

  /// Whether this is the signed-in member, and whether the server let them see
  /// the whole profile. `canViewFullProfile` is the server's answer, not a
  /// client-side guess — a locked profile arrives already stripped.
  final bool isSelf;
  final bool canViewFullProfile;

  /// "İzmir, TR ➜ Paterson, NJ", or just the US side when there is no origin.
  /// Null when we know neither, which is what the screen turns into a
  /// "Nereden geldin?" prompt.
  String? get journeyLine {
    final here = [city, state].where((part) => (part ?? '').isNotEmpty).join(', ');
    final origin = originCity;
    if (origin == null || origin.isEmpty) return here.isEmpty ? null : here;
    final from = originCountry == null ? origin : '$origin, $originCountry';
    return here.isEmpty ? from : '$from ➜ $here';
  }

  UserProfile copyWith({
    String? displayName,
    String? username,
    String? city,
    String? state,
    List<String>? interests,
    String? avatarUrl,
    ProfileVisibility? visibility,
    bool? isOnboardingComplete,
    String? bio,
    String? originCity,
    String? originCountry,
    bool? bornInUs,
    int? arrivedMonth,
    int? arrivedYear,
    String? primaryIntent,
    bool? identityVerified,
    List<ProfileBadge>? showcasedBadges,
    JourneySummary? journey,
    int? postCount,
    int? friendCount,
    int? followerCount,
    int? followingCount,
    int? badgeCount,
    bool? viewerFollows,
    bool? followsViewer,
    bool? isSelf,
    bool? canViewFullProfile,
  }) => UserProfile(
    id: id,
    displayName: displayName ?? this.displayName,
    email: email,
    username: username ?? this.username,
    city: city ?? this.city,
    state: state ?? this.state,
    interests: interests ?? this.interests,
    avatarUrl: avatarUrl ?? this.avatarUrl,
    visibility: visibility ?? this.visibility,
    isOnboardingComplete: isOnboardingComplete ?? this.isOnboardingComplete,
    bio: bio ?? this.bio,
    originCity: originCity ?? this.originCity,
    originCountry: originCountry ?? this.originCountry,
    bornInUs: bornInUs ?? this.bornInUs,
    arrivedMonth: arrivedMonth ?? this.arrivedMonth,
    arrivedYear: arrivedYear ?? this.arrivedYear,
    primaryIntent: primaryIntent ?? this.primaryIntent,
    identityVerified: identityVerified ?? this.identityVerified,
    showcasedBadges: showcasedBadges ?? this.showcasedBadges,
    journey: journey ?? this.journey,
    postCount: postCount ?? this.postCount,
    friendCount: friendCount ?? this.friendCount,
    followerCount: followerCount ?? this.followerCount,
    followingCount: followingCount ?? this.followingCount,
    badgeCount: badgeCount ?? this.badgeCount,
    viewerFollows: viewerFollows ?? this.viewerFollows,
    followsViewer: followsViewer ?? this.followsViewer,
    isSelf: isSelf ?? this.isSelf,
    canViewFullProfile: canViewFullProfile ?? this.canViewFullProfile,
  );
}

/// One cell of the Instagram-style grid.
class ProfilePost {
  const ProfilePost({
    required this.id,
    required this.message,
    required this.createdAt,
    this.thumbnailUrl,
    this.likes = 0,
    this.comments = 0,
    this.archived = false,
    this.pinned = false,
    this.commentsEnabled = true,
  });

  final String id;
  final String message;
  final DateTime createdAt;
  final String? thumbnailUrl;
  final int likes;
  final int comments;
  final bool archived;

  /// Izgaranın başına sabitlenmiş mi. Sunucu sıralamayı da buna göre yapıyor;
  /// ekran yalnızca rozetini çiziyor.
  final bool pinned;

  /// Yorumlara açık mı. Kapalıyken yorum kutusu hiç açılmıyor - açılıp da
  /// gönderilen yorumun reddedilmesi, kapatmayı işlevsiz göstermek olurdu.
  final bool commentsEnabled;

  ProfilePost copyWith({bool? pinned, bool? commentsEnabled}) => ProfilePost(
    id: id,
    message: message,
    createdAt: createdAt,
    thumbnailUrl: thumbnailUrl,
    likes: likes,
    comments: comments,
    archived: archived,
    pinned: pinned ?? this.pinned,
    commentsEnabled: commentsEnabled ?? this.commentsEnabled,
  );
}
