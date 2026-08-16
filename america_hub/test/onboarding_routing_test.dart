import 'package:america_hub/core/storage/in_memory_session_store.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/auth/application/auth_controller.dart';
import 'package:america_hub/features/auth/data/repositories/mock_auth_repository.dart';
import 'package:america_hub/features/auth/domain/entities/onboarding_draft.dart';
import 'package:america_hub/features/auth/domain/entities/onboarding_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// Returns whatever profile the test hands it, so both sides of the branch can
/// be exercised without a server.
class _RepositoryWithProfile extends MockAuthRepository {
  _RepositoryWithProfile(this.profile);

  final OnboardingProfile profile;
  int reads = 0;

  @override
  Future<OnboardingProfile> getOnboarding() async {
    reads++;
    return profile;
  }
}

/// Profili hic veremeyen bir sunucu.
class _RepositoryWithoutProfile extends MockAuthRepository {
  int reads = 0;

  @override
  Future<OnboardingProfile> getOnboarding() async {
    reads++;
    throw Exception('Profil servisi yanit vermedi.');
  }
}

void main() {
  AuthController controllerFor(MockAuthRepository repository) =>
      AuthController(
        repository: repository,
        sessionStore: InMemorySessionStore(),
        tokenStore: InMemoryTokenStore(),
      );

  // `needsOnboarding` is the single flag AppRouter branches on after a
  // successful sign-in; sending every login to onboarding regardless is what
  // made the setup screen reappear on every launch.
  test('a member who finished onboarding does not need it again', () async {
    final repository = _RepositoryWithProfile(
      const OnboardingProfile(
        completed: true,
        city: 'Paterson',
        countryCode: 'US',
        regionCode: 'NJ',
        interests: ['community_meet'],
        primaryIntent: 'community',
      ),
    );
    final controller = controllerFor(repository);

    await controller.signIn('member@turksquare.app', 'Sifre-1234!');

    expect(controller.needsOnboarding, isFalse);
    // The profile is read once while authenticating, so the branch costs no
    // extra round trip.
    expect(repository.reads, 1);
  });

  test('a member who never finished onboarding still needs it', () async {
    final controller = controllerFor(
      _RepositoryWithProfile(const OnboardingProfile(completed: false)),
    );

    await controller.signIn('member@turksquare.app', 'Sifre-1234!');

    expect(controller.needsOnboarding, isTrue);
  });

  test('signing in over the phone reads the same flag', () async {
    final controller = controllerFor(
      _RepositoryWithProfile(const OnboardingProfile(completed: true)),
    );

    await controller.signInWithPhone('+15551234567', '123456');

    expect(controller.needsOnboarding, isFalse);
  });

  test('completing onboarding flips the flag without another request', () async {
    final repository = _RepositoryWithProfile(
      const OnboardingProfile(completed: false),
    );
    final controller = controllerFor(repository);
    await controller.signIn('member@turksquare.app', 'Sifre-1234!');
    expect(controller.needsOnboarding, isTrue);

    await controller.saveOnboarding(
      const OnboardingDraft(
        city: 'Jersey City',
        countryCode: 'US',
        regionCode: 'NJ',
        interests: ['job_seeking'],
        primaryIntent: 'job_seeking',
        arrivedMonth: 3,
        arrivedYear: 2019,
      ),
    );

    expect(controller.needsOnboarding, isFalse);
    expect(controller.onboarding?.arrivedYear, 2019);
    expect(repository.reads, 1);
  });

  // Olculemeyen bir sey "tamamlanmamis" degil. Sunucu bir an cevap
  // vermediginde uye sihirbaza dusuyor, sehrini ve gelis tarihini yeniden
  // yaziyor ve gercek profilinin ustune kaydediyordu.
  test('kurulum durumu okunamadiysa bu bir "tamamlanmadi" cevabi degil', () async {
    final repository = _RepositoryWithoutProfile();
    final controller = controllerFor(repository);

    await controller.signIn('member@turksquare.app', 'Sifre-1234!');

    expect(repository.reads, 1);
    // Giris basarili: okunamayan tek sey kurulumun bitip bitmedigi.
    expect(controller.isAuthenticated, isTrue);
    expect(controller.onboardingUnknown, isTrue);
  });

  test('cevap gelince bilinmeyen bayragi kalkar', () async {
    final controller = controllerFor(_RepositoryWithoutProfile());
    await controller.signIn('member@turksquare.app', 'Sifre-1234!');
    expect(controller.onboardingUnknown, isTrue);

    await controller.saveOnboarding(
      const OnboardingDraft(
        city: 'Paterson',
        countryCode: 'US',
        regionCode: 'NJ',
        interests: ['community_meet'],
        primaryIntent: 'community',
      ),
    );

    expect(controller.onboardingUnknown, isFalse);
    expect(controller.needsOnboarding, isFalse);
  });

  test('okunabilen bir profil bilinmeyen birakmaz', () async {
    final controller = controllerFor(
      _RepositoryWithProfile(const OnboardingProfile(completed: false)),
    );

    await controller.signIn('member@turksquare.app', 'Sifre-1234!');

    expect(controller.onboardingUnknown, isFalse);
    expect(controller.needsOnboarding, isTrue);
  });

  test('signing out clears the cached profile', () async {
    final controller = controllerFor(
      _RepositoryWithProfile(const OnboardingProfile(completed: true)),
    );
    await controller.signIn('member@turksquare.app', 'Sifre-1234!');

    await controller.signOut();

    // Nothing is known about the next member yet, so the safe answer is to ask.
    expect(controller.onboarding, isNull);
    expect(controller.needsOnboarding, isTrue);
  });
}
