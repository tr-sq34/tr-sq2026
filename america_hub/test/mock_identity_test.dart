import 'package:america_hub/core/cache/cache_store.dart';
import 'package:america_hub/features/auth/data/repositories/mock_auth_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_media_upload_repository.dart';
import 'package:america_hub/features/community/domain/entities/community_post.dart';
import 'package:america_hub/features/community/domain/entities/post_media_upload.dart';
import 'package:america_hub/features/auth/domain/entities/onboarding_draft.dart';
import 'package:america_hub/features/profile/data/repositories/mock_profile_repository.dart';
import 'package:america_hub/features/profile/domain/entities/user_profile.dart';
import 'package:flutter_test/flutter_test.dart';

/// The mock stack as `main.dart` wires it: one store and one auth repository
/// shared by everything that needs to know who is signed in.
({
  MockAuthRepository auth,
  MockProfileRepository profile,
  MockMediaUploadRepository media,
  CacheStore store,
})
_stack({CacheStore? store}) {
  final cacheStore = store ?? MemoryCacheStore();
  final auth = MockAuthRepository(cacheStore: cacheStore);
  final media = MockMediaUploadRepository();
  return (
    auth: auth,
    profile: MockProfileRepository(
      auth: auth,
      cacheStore: cacheStore,
      media: media,
    ),
    media: media,
    store: cacheStore,
  );
}

const _draft = OnboardingDraft(
  city: 'Jersey City',
  regionCode: 'NJ',
  interests: ['yemek', 'is'],
  primaryIntent: 'newcomer',
  originCountry: 'TR',
  originCity: 'Trabzon',
  arrivedMonth: 3,
  arrivedYear: 2024,
);

void main() {
  test('the profile repeats the setup answers, not a fixture', () async {
    final stack = _stack();
    await stack.auth.signUp(
      name: 'Selin Aydın',
      email: 'Selin@example.com',
      password: 'GurbetYolu2026!',
    );
    await stack.auth.saveOnboarding(_draft);

    final profile = await stack.profile.getProfile();

    expect(profile.displayName, 'Selin Aydın');
    expect(profile.email, 'selin@example.com');
    expect(profile.city, 'Jersey City');
    expect(profile.state, 'NJ');
    expect(profile.originCity, 'Trabzon');
    expect(profile.arrivedYear, 2024);
    expect(profile.isOnboardingComplete, isTrue);
  });

  test('a member who has answered nothing is given nothing', () async {
    final stack = _stack();
    await stack.auth.signUp(
      name: 'Deniz Koç',
      email: 'deniz@example.com',
      password: 'GurbetYolu2026!',
    );

    final profile = await stack.profile.getProfile();

    expect(profile.displayName, 'Deniz Koç');
    // The complaint that started this: a brand new account was greeted as
    // somebody from İzmir living in Paterson.
    expect(profile.city, isNull);
    expect(profile.originCity, isNull);
    expect(profile.isOnboardingComplete, isFalse);
    expect(profile.identityVerified, isFalse);
    expect(await stack.profile.getPosts(profile.id), isEmpty);
  });

  test('the demo address keeps its fixture', () async {
    final stack = _stack();
    await stack.auth.signIn(
      email: MockAuthRepository.demoEmail,
      password: MockAuthRepository.demoPassword,
    );

    final profile = await stack.profile.getProfile();

    expect(profile.displayName, MockAuthRepository.demoName);
    expect(profile.city, 'Paterson');
    expect(profile.originCity, 'İzmir');
    expect(profile.identityVerified, isTrue);
    expect(await stack.profile.getPosts(profile.id), isNotEmpty);
  });

  test('a restart comes back as the same member, not as the demo', () async {
    final store = MemoryCacheStore();
    final first = _stack(store: store);
    await first.auth.signUp(
      name: 'Kaan Erdem',
      email: 'kaan@example.com',
      password: 'GurbetYolu2026!',
    );
    await first.auth.saveOnboarding(_draft);

    // A cold start: brand new objects, same disk.
    final second = _stack(store: store);
    final session = await second.auth.refreshSession(
      refreshToken: 'development-refresh-token',
    );
    final profile = await second.profile.getProfile();

    expect(session.user.email, 'kaan@example.com');
    expect(profile.displayName, 'Kaan Erdem');
    expect(profile.city, 'Jersey City');
    expect(profile.originCity, isNot('İzmir'));
  });

  test('a device nobody has signed in on refuses the session', () async {
    final stack = _stack();

    await expectLater(
      stack.auth.refreshSession(refreshToken: 'development-refresh-token'),
      throwsA(isA<AuthException>()),
    );
    // No session means no identity to answer with — not the demo's.
    final profile = await stack.profile.getProfile();
    expect(profile.city, isNull);
    expect(profile.identityVerified, isFalse);
  });

  test('signing out and back in lands on the same person', () async {
    final stack = _stack();
    await stack.auth.signUp(
      name: 'Ece Toprak',
      email: 'ece@example.com',
      password: 'GurbetYolu2026!',
    );
    await stack.auth.saveOnboarding(_draft);
    await stack.auth.signOut();

    expect(await stack.auth.checkEmailStatus(email: 'ece@example.com'), isTrue);
    await stack.auth.signIn(
      email: 'ece@example.com',
      password: 'GurbetYolu2026!',
    );
    final profile = await stack.profile.getProfile();

    expect(profile.displayName, 'Ece Toprak');
    expect(profile.city, 'Jersey City');
  });

  test('an uploaded avatar is stored as a drawable address, not an id', () async {
    final stack = _stack();
    await stack.auth.signUp(
      name: 'Barış Sezer',
      email: 'baris@example.com',
      password: 'GurbetYolu2026!',
    );

    const localId = 'upload-1';
    const localPath = '/tmp/picker/avatar.jpg';
    final progress = await stack.media
        .upload(
          const MediaUploadRequest(
            media: PostMediaUpload(
              localId: localId,
              type: PostMediaType.image,
              fileName: 'avatar.jpg',
              mimeType: 'image/jpeg',
              sizeBytes: 220 * 1024,
            ),
            localUri: localPath,
          ),
        )
        .last;
    expect(progress.status, MediaUploadStatus.ready);

    final profile = await stack.profile.updateProfile(
      avatarMediaId: (value: progress.media!.id),
    );

    // Storing the id here is what left the circle empty after every pick: the
    // address was never a URL and never a path, so nothing could draw it.
    expect(profile.avatarUrl, localPath);
    expect((await stack.profile.getProfile()).avatarUrl, localPath);
  });

  test('clearing the avatar brings the initials back', () async {
    final stack = _stack();
    await stack.auth.signUp(
      name: 'Mine Aksoy',
      email: 'mine@example.com',
      password: 'GurbetYolu2026!',
    );
    await stack.profile.updateProfile(avatarMediaId: (value: 'unknown-id'));

    final cleared = await stack.profile.updateProfile(
      avatarMediaId: (value: null),
    );

    expect(cleared.avatarUrl, isNull);
  });

  test('a bio survives a restart', () async {
    final store = MemoryCacheStore();
    final first = _stack(store: store);
    await first.auth.signUp(
      name: 'Onur Bal',
      email: 'onur@example.com',
      password: 'GurbetYolu2026!',
    );
    await first.profile.updateProfile(
      bio: (value: 'Paterson\'da yaşıyorum.'),
      visibility: ProfileVisibility.public,
    );

    final second = _stack(store: store);
    final profile = await second.profile.getProfile();

    expect(profile.bio, 'Paterson\'da yaşıyorum.');
    expect(profile.visibility, ProfileVisibility.public);
  });
}
