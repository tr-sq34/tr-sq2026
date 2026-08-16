import 'package:america_hub/core/storage/in_memory_session_store.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/auth/application/auth_controller.dart';
import 'package:america_hub/features/auth/data/repositories/mock_auth_repository.dart';
import 'package:america_hub/features/legal/domain/entities/legal_document.dart';
import 'package:america_hub/features/profile/application/profile_controller.dart';
import 'package:america_hub/features/profile/domain/entities/user_profile.dart';
import 'package:america_hub/features/profile/domain/repositories/profile_repository.dart';
import 'package:america_hub/features/profile/presentation/screens/account_settings_screen.dart';
import 'package:america_hub/features/profile/presentation/screens/archive_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_image_http.dart';

const _me = UserProfile(
  id: 'me',
  displayName: 'Alican Argınç',
  email: '',
  city: 'Paterson',
  state: 'NJ',
  isOnboardingComplete: true,
);

/// Yalnızca bu ekranın dokunduğu uçları tutan bir depo: arşiv listesi ve
/// görünürlük. Kalanı çağrılırsa test kırılsın diye boş.
class _FakeProfiles implements ProfileRepository {
  _FakeProfiles({this.archived = const []});

  UserProfile profile = _me;
  List<ProfilePost> archived;
  final List<String> unarchived = [];

  @override
  Future<UserProfile> getProfile() async => profile;

  @override
  Future<UserProfile> getProfileOf(String userId) async => profile;

  @override
  Future<UserProfile> saveProfile(UserProfile value) async => profile = value;

  @override
  Future<UserProfile> updateProfile({
    ({String? value})? bio,
    ({String? value})? avatarMediaId,
    ProfileVisibility? visibility,
    List<String>? showcasedBadges,
    ({String? value})? username,
  }) async => profile = profile.copyWith(visibility: visibility);

  @override
  Future<UsernameCheck> checkUsername(String username) async =>
      const UsernameCheck(available: true, message: 'Bu ad boşta.');

  @override
  Future<({List<FollowSummary> items, bool locked})> getFollowers(
    String userId,
  ) async => (items: const <FollowSummary>[], locked: false);

  @override
  Future<({List<FollowSummary> items, bool locked})> getFollowing(
    String userId,
  ) async => (items: const <FollowSummary>[], locked: false);

  @override
  Future<bool> follow(String userId) async => true;

  @override
  Future<bool> unfollow(String userId) async => false;

  @override
  Future<void> removeFollower(String userId) async {}

  @override
  Future<List<ProfilePost>> getPosts(
    String userId, {
    ProfilePostState state = ProfilePostState.active,
  }) async => state == ProfilePostState.archived ? archived : const [];

  @override
  Future<void> archivePost(String postId) async {}

  @override
  Future<void> unarchivePost(String postId) async {
    unarchived.add(postId);
    archived = archived.where((item) => item.id != postId).toList();
  }

  @override
  Future<({bool pinned, bool commentsEnabled})> setPostSettings(
    String postId, {
    bool? pinned,
    bool? commentsEnabled,
  }) async => (pinned: pinned ?? false, commentsEnabled: commentsEnabled ?? true);
}

/// Hesabı kapatma uçlarını kaydeden kimlik deposu. Kalan her şey mock'un
/// kendisi: bu testlerin derdi giriş akışı değil.
class _FakeAuth extends MockAuthRepository {
  bool frozen = false;
  String? deletePassword;

  /// Sunucunun yanlış şifreye verdiği cevabın taşıdığı kod.
  bool rejectPassword = false;

  @override
  Future<void> freezeAccount() async => frozen = true;

  @override
  Future<DateTime> requestAccountDeletion({required String password}) async {
    if (rejectPassword) {
      throw Exception('403 INVALID_CREDENTIALS Şifre doğrulanamadı.');
    }
    deletePassword = password;
    return DateTime(2026, 9, 14);
  }
}

Future<
  ({
    _FakeProfiles profiles,
    _FakeAuth auth,
    List<String> signOuts,
    List<LegalDocumentKind> legal,
  })
>
_pumpSettings(WidgetTester tester, {List<ProfilePost> archived = const []}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  installFakeImageHttp();

  final profiles = _FakeProfiles(archived: archived);
  final auth = _FakeAuth();
  final signOuts = <String>[];
  final legal = <LegalDocumentKind>[];
  final profileController = ProfileController(repository: profiles);
  await profileController.load();

  await tester.pumpWidget(
    MaterialApp(
      home: AccountSettingsScreen(
        profileController: profileController,
        authController: AuthController(
          repository: auth,
          sessionStore: InMemorySessionStore(),
          tokenStore: InMemoryTokenStore(),
        ),
        onSignOut: () async => signOuts.add('out'),
        onOpenLegal: legal.add,
      ),
    ),
  );
  await tester.pump();
  return (profiles: profiles, auth: auth, signOuts: signOuts, legal: legal);
}

void main() {
  testWidgets('arsiv hesap ayarlarinin altinda duruyor', (tester) async {
    final harness = await _pumpSettings(
      tester,
      archived: [
        ProfilePost(
          id: 'post-1',
          message: 'Arşive kaldırdığım paylaşım',
          createdAt: DateTime(2026, 3, 2),
          archived: true,
        ),
      ],
    );

    expect(find.text('Arşiv'), findsOneWidget);
    await tester.tap(find.text('Arşiv'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.byType(ArchiveScreen), findsOneWidget);
    expect(find.textContaining('Arşive kaldırdığım'), findsOneWidget);
    expect(find.textContaining('kimse göremiyor'), findsOneWidget);

    // Arşivden çıkarmak sunucuya gidiyor; liste oradan yeniden okunuyor.
    await tester.longPress(find.textContaining('Arşive kaldırdığım'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.tap(find.text('Arşivden çıkar'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(harness.profiles.unarchived, ['post-1']);
    expect(find.text('Arşivde bir şey yok.'), findsOneWidget);
  });

  testWidgets('bos arsiv sifir degil, ne oldugunu yaziyor', (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Arşiv'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('Arşivde bir şey yok.'), findsOneWidget);
    expect(find.textContaining('beğenileri ve yorumları burada'), findsOneWidget);
  });

  testWidgets('hesabi dondurmak once soruyor sonra oturumu kapatiyor', (tester) async {
    final harness = await _pumpSettings(tester);

    await tester.tap(find.text('Hesabı dondur'));
    await tester.pump();
    expect(find.text('Hesabın dondurulsun mu?'), findsOneWidget);
    expect(find.textContaining('silinmiyor'), findsOneWidget);

    // Vazgeçmek gerçekten vazgeçiyor.
    await tester.tap(find.text('Vazgeç'));
    await tester.pump();
    expect(harness.auth.frozen, isFalse);
    expect(harness.signOuts, isEmpty);

    await tester.tap(find.text('Hesabı dondur'));
    await tester.pump();
    await tester.tap(find.text('Dondur'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(harness.auth.frozen, isTrue);
    expect(harness.signOuts, ['out']);
  });

  testWidgets('hesabi silmek sifre soruyor ve tarihi soyluyor', (tester) async {
    final harness = await _pumpSettings(tester);

    await tester.ensureVisible(find.text('Hesabı sil'));
    await tester.pump();
    await tester.tap(find.text('Hesabı sil'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('Hesabını sil'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'dogru-sifre');
    await tester.pump();
    await tester.tap(find.text('Hesabımı sil'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(harness.auth.deletePassword, 'dogru-sifre');
    expect(find.text('Silme talebin alındı'), findsOneWidget);
    expect(find.textContaining('14 Eylül 2026'), findsOneWidget);

    await tester.tap(find.text('Anladım'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(harness.signOuts, ['out']);
  });

  testWidgets('yanlis sifre hesabi silmiyor ve nedenini yaziyor', (tester) async {
    final harness = await _pumpSettings(tester);
    harness.auth.rejectPassword = true;

    await tester.ensureVisible(find.text('Hesabı sil'));
    await tester.pump();
    await tester.tap(find.text('Hesabı sil'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.enterText(find.byType(TextField), 'yanlis');
    await tester.pump();
    await tester.tap(find.text('Hesabımı sil'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(harness.auth.deletePassword, isNull);
    expect(harness.signOuts, isEmpty);
    expect(
      find.text('Şifre doğrulanamadı. Hesabın olduğu gibi duruyor.'),
      findsOneWidget,
    );
  });

  testWidgets('gizlilik secimi sunucuya gidiyor', (tester) async {
    final harness = await _pumpSettings(tester);
    // Varsayılan gizli; testin bir şey değiştirdiğini görebilmek için diğer
    // uca geçiliyor.
    expect(harness.profiles.profile.visibility, ProfileVisibility.friendsOnly);

    await tester.tap(find.text('Herkese açık'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(harness.profiles.profile.visibility, ProfileVisibility.public);
    expect(find.text('Profilin herkese açık.'), findsOneWidget);
  });

  // Kayit olurken kabul edilen iki metin, kabul edildikten sonra uygulamanin
  // hicbir yerinden okunamiyordu. Kabul ettigi seyi sonradan okuyamamak,
  // kabul etmemisle ayni sey.
  testWidgets('yasal metinler hesap ayarlarindan acilabiliyor', (tester) async {
    final harness = await _pumpSettings(tester);

    final kosullar = find.text('Kullanım Koşulları');
    await tester.scrollUntilVisible(kosullar, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(kosullar);
    await tester.pumpAndSettle();

    final gizlilik = find.text('Gizlilik Politikası');
    await tester.scrollUntilVisible(gizlilik, 200, scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(gizlilik);
    await tester.pumpAndSettle();

    expect(harness.legal, [LegalDocumentKind.terms, LegalDocumentKind.privacy]);
  });
}
