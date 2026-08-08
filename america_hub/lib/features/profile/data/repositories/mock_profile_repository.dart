import '../../domain/entities/user_profile.dart';
import '../../domain/repositories/profile_repository.dart';

class MockProfileRepository implements ProfileRepository {
  UserProfile _profile = const UserProfile(
    id: 'local-user',
    displayName: 'Ahmet Yılmaz',
    email: 'member@turksquare.app',
    city: 'Paterson',
    state: 'New Jersey',
    originCity: 'İzmir',
    bio: 'Yeni insanlarla, iyi kahveyle ve memleket hikâyeleriyle tanışmayı seviyorum.',
    badges: ['Paterson Veteran', '3. Yıl', 'Sıla Hasreti'],
    favoritePlaces: ['Paterson Türk Marketi', 'Istanbul Cafe'],
    friendCount: 86,
    followerCount: 214,
    followingCount: 177,
    isOnboardingComplete: true,
  );

  @override
  Future<UserProfile> getProfile() async => _profile;

  @override
  Future<UserProfile> saveProfile(UserProfile profile) async {
    _profile = profile;
    return _profile;
  }
}
