import '../entities/user_profile.dart';

enum ProfilePostState { active, archived }

abstract interface class ProfileRepository {
  Future<UserProfile> getProfile();

  /// Someone else's profile. The server decides how much of it comes back, so a
  /// locked profile arrives with its fields already emptied and
  /// `canViewFullProfile` false.
  Future<UserProfile> getProfileOf(String userId);

  Future<UserProfile> saveProfile(UserProfile profile);

  /// Only the fields the member types into the app. Origin city and arrival date
  /// are onboarding answers and are edited through the identity service; sending
  /// them here would give one fact two writers.
  ///
  /// A field left out is left alone; an explicit null clears it. That is why
  /// [bio] and [avatarMediaId] are wrapped — a bare null could not tell the two
  /// apart.
  Future<UserProfile> updateProfile({
    ({String? value})? bio,
    ({String? value})? avatarMediaId,
    ProfileVisibility? visibility,
    List<String>? showcasedBadges,
  });

  Future<List<ProfilePost>> getPosts(
    String userId, {
    ProfilePostState state = ProfilePostState.active,
  });

  /// Hides a post from the feed and the grid without destroying it. Its
  /// comments, reactions and any open moderation report survive — that is the
  /// whole difference between archiving and deleting.
  Future<void> archivePost(String postId);
  Future<void> unarchivePost(String postId);
}
