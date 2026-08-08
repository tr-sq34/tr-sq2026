enum ProfileVisibility { public, friendsOnly }

class UserProfile {
  const UserProfile({
    required this.id,
    required this.displayName,
    required this.email,
    this.city,
    this.state,
    this.interests = const [],
    this.avatarUrl,
    this.visibility = ProfileVisibility.friendsOnly,
    this.isOnboardingComplete = false,
    this.bio = '',
    this.originCity,
    this.badges = const [],
    this.favoritePlaces = const [],
    this.friendCount = 0,
    this.followerCount = 0,
    this.followingCount = 0,
  });

  final String id;
  final String displayName;
  final String email;
  final String? city;
  final String? state;
  final List<String> interests;
  final String? avatarUrl;
  final ProfileVisibility visibility;
  final bool isOnboardingComplete;
  final String bio;
  final String? originCity;
  final List<String> badges;
  final List<String> favoritePlaces;
  final int friendCount;
  final int followerCount;
  final int followingCount;

  UserProfile copyWith({
    String? displayName,
    String? city,
    String? state,
    List<String>? interests,
    String? avatarUrl,
    ProfileVisibility? visibility,
    bool? isOnboardingComplete,
    String? bio,
    String? originCity,
    List<String>? badges,
    List<String>? favoritePlaces,
    int? friendCount,
    int? followerCount,
    int? followingCount,
  }) =>
      UserProfile(
        id: id,
        displayName: displayName ?? this.displayName,
        email: email,
        city: city ?? this.city,
        state: state ?? this.state,
        interests: interests ?? this.interests,
        avatarUrl: avatarUrl ?? this.avatarUrl,
        visibility: visibility ?? this.visibility,
        isOnboardingComplete: isOnboardingComplete ?? this.isOnboardingComplete,
        bio: bio ?? this.bio,
        originCity: originCity ?? this.originCity,
        badges: badges ?? this.badges,
        favoritePlaces: favoritePlaces ?? this.favoritePlaces,
        friendCount: friendCount ?? this.friendCount,
        followerCount: followerCount ?? this.followerCount,
        followingCount: followingCount ?? this.followingCount,
      );
}
