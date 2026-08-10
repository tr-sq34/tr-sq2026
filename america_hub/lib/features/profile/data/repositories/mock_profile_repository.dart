import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';

/// Offline stand-in for the community profile service.
///
/// It carries a name and a city because the screen is unbuildable without them,
/// and nothing else that pretends to be real: no invented badges, no invented
/// friends, no favourite restaurants. What the member has not earned or written
/// shows up empty here exactly as it will against the live service.
class MockProfileRepository implements ProfileRepository {
  MockProfileRepository();

  UserProfile _profile = const UserProfile(
    id: 'local-user',
    displayName: 'Demo Kullanıcı',
    email: 'member@turksquare.app',
    city: 'Paterson',
    state: 'NJ',
    originCity: 'İzmir',
    originCountry: 'TR',
    arrivedMonth: 8,
    arrivedYear: 2019,
    isOnboardingComplete: true,
  );

  final List<ProfilePost> _posts = [
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
  Future<UserProfile> getProfile() async => _profile;

  @override
  Future<UserProfile> getProfileOf(String userId) async =>
      _profile.copyWith(isSelf: false, canViewFullProfile: true);

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    _profile = profile;
    return _profile;
  }

  @override
  Future<UserProfile> updateProfile({
    ({String? value})? bio,
    ({String? value})? avatarMediaId,
    ProfileVisibility? visibility,
    List<String>? showcasedBadges,
  }) async {
    _profile = _profile.copyWith(
      bio: bio?.value ?? _profile.bio,
      avatarUrl: avatarMediaId?.value ?? _profile.avatarUrl,
      visibility: visibility,
    );
    return _profile;
  }

  @override
  Future<List<ProfilePost>> getPosts(
    String userId, {
    ProfilePostState state = ProfilePostState.active,
  }) async => state == ProfilePostState.archived
      ? List.unmodifiable(_archived)
      : List.unmodifiable(_posts);

  @override
  Future<void> archivePost(String postId) async {
    final index = _posts.indexWhere((post) => post.id == postId);
    if (index < 0) return;
    final post = _posts.removeAt(index);
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
    _posts.insert(0, ProfilePost(
      id: post.id,
      message: post.message,
      createdAt: post.createdAt,
      thumbnailUrl: post.thumbnailUrl,
      likes: post.likes,
      comments: post.comments,
    ));
  }
}
