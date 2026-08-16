import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_endpoints.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';

/// The profile as the community service serves it.
///
/// Every access decision — whether a viewer sees the origin city, the bio, the
/// friend list — has already been made server-side. This class does not filter;
/// it reads `canViewFullProfile` and lets the screen draw a lock.
class ApiProfileRepository implements ProfileRepository {
  ApiProfileRepository({required ApiClient client}) : _client = client;

  final ApiClient _client;

  @override
  Future<UserProfile> getProfile() async {
    final response = await _client.get<Map<String, dynamic>>(ApiEndpoints.communityProfileMe);
    return _profileFrom(response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<UserProfile> getProfileOf(String userId) async {
    final response = await _client.get<Map<String, dynamic>>(ApiEndpoints.communityProfile(userId));
    return _profileFrom(response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<UserProfile> saveProfile(UserProfile profile) => updateProfile(
    bio: (value: profile.bio),
    visibility: profile.visibility,
  );

  @override
  Future<UserProfile> updateProfile({
    ({String? value})? bio,
    ({String? value})? avatarMediaId,
    ProfileVisibility? visibility,
    List<String>? showcasedBadges,
    ({String? value})? username,
  }) async {
    // Only the keys the caller actually passed are sent. An omitted key means
    // "leave it alone" on the server; including it with null would clear it.
    final body = <String, dynamic>{
      if (bio != null) 'bio': bio.value,
      if (avatarMediaId != null) 'avatarMediaId': avatarMediaId.value,
      if (visibility != null)
        'visibility': visibility == ProfileVisibility.public ? 'public' : 'friends_only',
      'showcasedBadges': ?showcasedBadges,
      if (username != null) 'username': username.value,
    };
    final response = await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.communityProfileMe,
      data: body,
    );
    return _profileFrom(response.data!['data'] as Map<String, dynamic>);
  }

  @override
  Future<List<ProfilePost>> getPosts(
    String userId, {
    ProfilePostState state = ProfilePostState.active,
  }) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityProfilePosts(userId),
      queryParameters: {'state': state.name},
    );
    return (response.data!['data'] as List<dynamic>)
        .map((raw) => _postFrom(raw as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> archivePost(String postId) =>
      _client.post<void>(ApiEndpoints.communityPostArchive(postId));

  @override
  Future<void> unarchivePost(String postId) =>
      _client.delete<void>(ApiEndpoints.communityPostArchive(postId));

  @override
  Future<({bool pinned, bool commentsEnabled})> setPostSettings(
    String postId, {
    bool? pinned,
    bool? commentsEnabled,
  }) async {
    final response = await _client.patch<Map<String, dynamic>>(
      ApiEndpoints.communityPostSettings(postId),
      data: {
        'pinned': ?pinned,
        'commentsEnabled': ?commentsEnabled,
      },
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? const {};
    // Sunucunun döndüğü hâl esas alınıyor: sabit sınırı dolduğunda istek
    // reddediliyor ve istenen değer gerçekleşmemiş oluyor.
    return (
      pinned: data['pinned'] as bool? ?? pinned ?? false,
      commentsEnabled: data['commentsEnabled'] as bool? ?? commentsEnabled ?? true,
    );
  }

  @override
  Future<UsernameCheck> checkUsername(String username) async {
    final response = await _client.get<Map<String, dynamic>>(
      ApiEndpoints.communityUsernameAvailable,
      queryParameters: {'username': username},
    );
    final data = response.data!['data'] as Map<String, dynamic>;
    return UsernameCheck(
      available: data['available'] as bool? ?? false,
      // Sunucu neden reddettiğini yazıyla söylüyor; burada yeniden yazmak, iki
      // yerde iki farklı cümle demek olurdu.
      message: data['message'] as String? ?? 'Kullanıcı adı denetlenemedi.',
    );
  }

  @override
  Future<({List<FollowSummary> items, bool locked})> getFollowers(String userId) =>
      _followList(ApiEndpoints.communityFollowers(userId));

  @override
  Future<({List<FollowSummary> items, bool locked})> getFollowing(String userId) =>
      _followList(ApiEndpoints.communityFollowing(userId));

  Future<({List<FollowSummary> items, bool locked})> _followList(String path) async {
    final response = await _client.get<Map<String, dynamic>>(path);
    final body = response.data!;
    final meta = body['meta'] as Map<String, dynamic>? ?? const {};
    return (
      items: (body['data'] as List<dynamic>)
          .map((raw) => _followFrom(raw as Map<String, dynamic>))
          .toList(),
      locked: meta['locked'] as bool? ?? false,
    );
  }

  @override
  Future<bool> follow(String userId) async {
    final response = await _client.post<Map<String, dynamic>>(
      ApiEndpoints.communityFollow(userId),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? const {};
    return data['following'] as bool? ?? true;
  }

  @override
  Future<bool> unfollow(String userId) async {
    final response = await _client.delete<Map<String, dynamic>>(
      ApiEndpoints.communityFollow(userId),
    );
    final data = response.data?['data'] as Map<String, dynamic>? ?? const {};
    // Arkadaşlık sürüyorsa sunucu hâlâ "takip ediliyor" diyor; ekran düğmeyi
    // ona göre bırakıyor.
    return data['following'] as bool? ?? false;
  }

  @override
  Future<void> removeFollower(String userId) =>
      _client.delete<void>(ApiEndpoints.communityFollower(userId));

  FollowSummary _followFrom(Map<String, dynamic> json) => FollowSummary(
    userId: json['userId'] as String,
    displayName: json['displayName'] as String? ?? 'TurkSquare üyesi',
    username: json['username'] as String?,
    city: json['city'] as String?,
    regionCode: json['regionCode'] as String?,
    avatarUrl: json['avatarUrl'] as String?,
    viewerFollows: json['viewerFollows'] as bool? ?? false,
  );

  UserProfile _profileFrom(Map<String, dynamic> json) {
    final counts = json['counts'] as Map<String, dynamic>? ?? const {};
    final journey = json['journey'] as Map<String, dynamic>? ?? const {};
    return UserProfile(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? 'TurkSquare üyesi',
      username: json['username'] as String?,
      // Community never sees the address; it is identity's, and the profile
      // screen does not show it. Kept empty rather than faked.
      email: '',
      city: json['city'] as String?,
      state: json['regionCode'] as String?,
      interests: (json['interests'] as List<dynamic>? ?? const []).cast<String>(),
      avatarUrl: json['avatarUrl'] as String?,
      visibility: json['visibility'] == 'public'
          ? ProfileVisibility.public
          : ProfileVisibility.friendsOnly,
      isOnboardingComplete: true,
      bio: json['bio'] as String? ?? '',
      originCity: json['originCity'] as String?,
      originCountry: json['originCountry'] as String?,
      bornInUs: json['bornInUs'] as bool? ?? false,
      arrivedMonth: (json['arrivedMonth'] as num?)?.toInt(),
      arrivedYear: (json['arrivedYear'] as num?)?.toInt(),
      primaryIntent: json['primaryIntent'] as String?,
      identityVerified: json['identityVerified'] as bool? ?? false,
      showcasedBadges: (json['showcasedBadges'] as List<dynamic>? ?? const [])
          .map((raw) {
            final badge = raw as Map<String, dynamic>;
            return ProfileBadge(
              code: badge['code'] as String,
              title: badge['title'] as String? ?? '',
              icon: badge['icon'] as String? ?? 'star',
              tier: badgeTierFrom(badge['tier'] as String?),
            );
          })
          .toList(),
      journey: JourneySummary(
        points: (journey['points'] as num?)?.toInt() ?? 0,
        level: (journey['level'] as num?)?.toInt() ?? 1,
        levelTitle: journey['levelTitle'] as String? ?? 'Fresh off the Boat',
        nextLevelPoints: (journey['nextLevelPoints'] as num?)?.toInt(),
        streakDays: (journey['streakDays'] as num?)?.toInt() ?? 0,
      ),
      postCount: (counts['posts'] as num?)?.toInt() ?? 0,
      friendCount: (counts['friends'] as num?)?.toInt() ?? 0,
      followerCount: (counts['followers'] as num?)?.toInt() ?? 0,
      followingCount: (counts['following'] as num?)?.toInt() ?? 0,
      badgeCount: (counts['badges'] as num?)?.toInt() ?? 0,
      viewerFollows: json['viewerFollows'] as bool? ?? false,
      followsViewer: json['followsViewer'] as bool? ?? false,
      isSelf: json['isSelf'] as bool? ?? false,
      canViewFullProfile: json['canViewFullProfile'] as bool? ?? false,
    );
  }

  ProfilePost _postFrom(Map<String, dynamic> json) => ProfilePost(
    id: json['id'] as String,
    message: json['message'] as String? ?? '',
    createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    thumbnailUrl: json['thumbnailUrl'] as String?,
    likes: (json['likes'] as num?)?.toInt() ?? 0,
    comments: (json['comments'] as num?)?.toInt() ?? 0,
    archived: json['archived'] as bool? ?? false,
    pinned: json['pinned'] as bool? ?? false,
    commentsEnabled: json['commentsEnabled'] as bool? ?? true,
  );
}
