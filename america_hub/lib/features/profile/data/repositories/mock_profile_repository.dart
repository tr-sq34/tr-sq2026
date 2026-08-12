import 'dart:convert';

import '../../../../core/cache/cache_store.dart';
import '../../../auth/data/repositories/mock_auth_repository.dart';
import '../../../community/data/repositories/mock_media_upload_repository.dart';
import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';

/// Offline stand-in for the community profile service.
///
/// It invents nobody. The name and email come from the session, the city and
/// origin come from the answers the member typed into the setup steps, and
/// anything they have not written stays empty — exactly as it will against the
/// live service. Returning a fixed fixture here is what used to greet every new
/// account as someone else, living in a city they had never chosen.
class MockProfileRepository implements ProfileRepository {
  /// Every argument is optional so tests and widget previews can build one with
  /// no wiring; `main.dart` passes the same instances the rest of the app uses.
  MockProfileRepository({
    MockAuthRepository? auth,
    CacheStore? cacheStore,
    MockMediaUploadRepository? media,
  }) : _auth = auth ?? MockAuthRepository(),
       _store = cacheStore ?? MemoryCacheStore(),
       _media = media;

  final MockAuthRepository _auth;
  final CacheStore _store;

  /// Resolves an upload id to the file it was read from. Null in tests that do
  /// not upload anything, in which case the id is stored unchanged and the
  /// avatar simply falls back to initials.
  final MockMediaUploadRepository? _media;

  static String _editsKey(String email) => 'mock_profile.$email';

  /// The demo account's two posts. They stay pinned to that one address: a
  /// freshly registered member has written nothing, and a grid full of somebody
  /// else's posts is the same lie as somebody else's city.
  final List<ProfilePost> _demoPosts = [
    ProfilePost(
      id: 'mock-post-1',
      message: 'Paterson\'da yeni açılan fırını denedim, simit gerçekten iyi.',
      createdAt: DateTime(2026, 7, 2),
      likes: 12,
      comments: 3,
    ),
    ProfilePost(
      id: 'mock-post-2',
      message: 'DMV randevusu için sabah 7\'de gitmek işe yarıyor.',
      createdAt: DateTime(2026, 6, 18),
      likes: 34,
      comments: 9,
    ),
  ];
  final List<ProfilePost> _archived = [];

  @override
  Future<UserProfile> getProfile() async {
    // Reading the onboarding first also restores the session from disk, so a
    // cold start knows who it is before it is asked for a name.
    final onboarding = await _auth.getOnboarding();
    final email = _auth.currentEmail ?? '';
    final isDemo = email == MockAuthRepository.demoEmail;
    final edits = await _readEdits(email);

    return UserProfile(
      id: _auth.currentUserId ?? 'local-user',
      displayName: _auth.currentDisplayName ?? email,
      email: email,
      city: onboarding.city,
      state: onboarding.regionCode,
      interests: onboarding.interests,
      avatarUrl: edits['avatarUrl'] as String?,
      visibility: edits['visibility'] == 'public'
          ? ProfileVisibility.public
          : ProfileVisibility.friendsOnly,
      isOnboardingComplete: onboarding.completed,
      bio: edits['bio'] as String? ?? '',
      originCity: onboarding.originCity,
      originCountry: onboarding.originCountry,
      bornInUs: onboarding.bornInUs,
      arrivedMonth: onboarding.arrivedMonth,
      arrivedYear: onboarding.arrivedYear,
      primaryIntent: onboarding.primaryIntent,
      // Verification is a decision the verification service makes. The demo
      // account carries it so a reviewer can see the ✓ next to a name; nobody
      // else gets it for free.
      identityVerified: isDemo,
      postCount: isDemo ? _demoPosts.length : 0,
    );
  }

  @override
  Future<UserProfile> getProfileOf(String userId) async {
    final self = await getProfile();
    return self.copyWith(isSelf: false, canViewFullProfile: true);
  }

  @override
  Future<UserProfile> saveProfile(UserProfile profile) => updateProfile(
    bio: (value: profile.bio),
    avatarMediaId: (value: profile.avatarUrl),
    visibility: profile.visibility,
  );

  @override
  Future<UserProfile> updateProfile({
    ({String? value})? bio,
    ({String? value})? avatarMediaId,
    ProfileVisibility? visibility,
    List<String>? showcasedBadges,
  }) async {
    final email = _auth.currentEmail ?? '';
    final edits = await _readEdits(email);
    if (bio != null) edits['bio'] = bio.value;
    if (avatarMediaId != null) {
      // The id is not an address. Turning it into one is the media service's
      // job on the server and the upload registry's job here; storing the id
      // raw is what left the avatar blank after every pick.
      final id = avatarMediaId.value;
      edits['avatarUrl'] = id == null ? null : (_media?.resolve(id) ?? id);
    }
    if (visibility != null) {
      edits['visibility'] = visibility == ProfileVisibility.public
          ? 'public'
          : 'friendsOnly';
    }
    await _store.write(_editsKey(email), jsonEncode(edits));
    return getProfile();
  }

  @override
  Future<List<ProfilePost>> getPosts(
    String userId, {
    ProfilePostState state = ProfilePostState.active,
  }) async {
    if (_auth.currentEmail != MockAuthRepository.demoEmail) return const [];
    return state == ProfilePostState.archived
        ? List.unmodifiable(_archived)
        : List.unmodifiable(_demoPosts);
  }

  @override
  Future<void> archivePost(String postId) async {
    final index = _demoPosts.indexWhere((post) => post.id == postId);
    if (index < 0) return;
    final post = _demoPosts.removeAt(index);
    _archived.insert(0, ProfilePost(
      id: post.id,
      message: post.message,
      createdAt: post.createdAt,
      thumbnailUrl: post.thumbnailUrl,
      likes: post.likes,
      comments: post.comments,
      archived: true,
    ));
  }

  @override
  Future<void> unarchivePost(String postId) async {
    final index = _archived.indexWhere((post) => post.id == postId);
    if (index < 0) return;
    final post = _archived.removeAt(index);
    _demoPosts.insert(0, ProfilePost(
      id: post.id,
      message: post.message,
      createdAt: post.createdAt,
      thumbnailUrl: post.thumbnailUrl,
      likes: post.likes,
      comments: post.comments,
    ));
  }

  /// The handful of fields the member edits from inside the app, kept apart
  /// from the onboarding answers because those have a different writer.
  Future<Map<String, dynamic>> _readEdits(String email) async {
    if (await _store.read(_editsKey(email)) case final raw?) {
      return (jsonDecode(raw) as Map<String, dynamic>);
    }
    return <String, dynamic>{};
  }
}
