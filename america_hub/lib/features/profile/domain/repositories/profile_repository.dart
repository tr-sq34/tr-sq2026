import '../entities/user_profile.dart';

abstract interface class ProfileRepository {
  Future<UserProfile> getProfile();
  Future<UserProfile> saveProfile(UserProfile profile);
}
