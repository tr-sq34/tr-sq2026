import 'package:america_hub/features/profile/application/profile_controller.dart';
import 'package:america_hub/features/profile/domain/entities/user_profile.dart';
import 'package:america_hub/features/profile/domain/repositories/profile_repository.dart';
import 'package:america_hub/features/profile/presentation/screens/member_profile_screen.dart';
import 'package:america_hub/features/profile/presentation/widgets/follow_list_sheet.dart';
import 'package:america_hub/features/profile/presentation/widgets/username_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Başkasının profili, kullanıcı adı ve takip listeleri.
///
/// Buradaki her senaryonun ortak derdi aynı: bir isteğin cevapsız kalması ya da
/// bir profilin kapalı olması, ekranda boşluk olarak değil cümle olarak
/// görünmeli.
void main() {
  testWidgets('gizli profil biyografiyi ve rozetleri gösterip kalanını açıklıyor', (
    tester,
  ) async {
    final repository = _FakeProfiles(
      _profile(
        canViewFullProfile: false,
        bio: 'Iki yildir Paterson\'dayim.',
        showcasedBadges: const [
          ProfileBadge(code: 'first_post', title: 'Ilk Adim'),
        ],
      ),
    );
    await _pumpMember(tester, repository);

    expect(find.text('Iki yildir Paterson\'dayim.'), findsOneWidget);
    expect(find.text('Ilk Adim'), findsOneWidget);
    expect(find.text('Bu profil gizli'), findsOneWidget);
    // Kilitli profilde ızgara hiç çizilmiyor: boş bir ızgara "hiç paylaşmamış"
    // demek olurdu, oysa paylaşımları var, görme iznimiz yok.
    expect(find.text('Henüz bir paylaşım yok.'), findsNothing);
  });

  testWidgets('takip et düğmesi sunucuya gidiyor ve durumu oradan okuyor', (
    tester,
  ) async {
    final repository = _FakeProfiles(_profile());
    await _pumpMember(tester, repository);

    expect(find.text('Takip et'), findsOneWidget);
    await tester.tap(find.text('Takip et'));
    await tester.pumpAndSettle();

    expect(repository.followed, ['member-elif']);
    expect(find.text('Takiptesin'), findsOneWidget);
    expect(find.text('13'), findsOneWidget, reason: 'takipçi sayısı sunucudan');
  });

  testWidgets('takip isteği cevapsız kalınca düğme eski halinde kalıyor', (
    tester,
  ) async {
    final repository = _FakeProfiles(_profile(), failFollow: true);
    await _pumpMember(tester, repository);

    await tester.tap(find.text('Takip et'));
    await tester.pumpAndSettle();

    expect(find.text('İşlem tamamlanamadı. Tekrar dene.'), findsOneWidget);
    expect(find.text('Takip et'), findsOneWidget);
    expect(find.text('Takiptesin'), findsNothing);
  });

  testWidgets('kilitli takipçi listesi boş liste gibi görünmüyor', (tester) async {
    final repository = _FakeProfiles(_profile(), followersLocked: true);
    final controller = ProfileController(repository: repository);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FollowListSheet(controller: controller, profile: _profile()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Bu liste gizli'), findsOneWidget);
    expect(find.text('Henüz takipçin yok'), findsNothing);
  });

  testWidgets('alınmış kullanıcı adı kaydedilemiyor ve nedeni yazıyor', (
    tester,
  ) async {
    final repository = _FakeProfiles(_profile(isSelf: true));
    final controller = ProfileController(repository: repository);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsernameSheet(controller: controller, profile: _profile(isSelf: true)),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'ahmet');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Bu kullanıcı adı alınmış.'), findsOneWidget);
    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
  });

  testWidgets('denetim cevapsız kalırsa ad müsait sayılmıyor', (tester) async {
    final repository = _FakeProfiles(_profile(isSelf: true), failCheck: true);
    final controller = ProfileController(repository: repository);
    await controller.load();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: UsernameSheet(controller: controller, profile: _profile(isSelf: true)),
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), 'yenibirad');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.text('Kullanıcı adı şu anda denetlenemedi.'), findsOneWidget);
    final save = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(save.onPressed, isNull);
  });
}

Future<void> _pumpMember(WidgetTester tester, _FakeProfiles repository) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MemberProfileScreen(
        userId: 'member-elif',
        controller: ProfileController(repository: repository),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

UserProfile _profile({
  bool canViewFullProfile = true,
  bool isSelf = false,
  String bio = '',
  List<ProfileBadge> showcasedBadges = const [],
}) => UserProfile(
  id: 'member-elif',
  displayName: 'Elif Demir',
  email: 'elif@example.com',
  username: 'elif',
  city: 'Paterson',
  state: 'NJ',
  bio: bio,
  showcasedBadges: showcasedBadges,
  followerCount: 12,
  followingCount: 4,
  isSelf: isSelf,
  canViewFullProfile: canViewFullProfile,
);

class _FakeProfiles implements ProfileRepository {
  _FakeProfiles(
    this._profile, {
    this.failFollow = false,
    this.failCheck = false,
    this.followersLocked = false,
  });

  UserProfile _profile;
  final bool failFollow;
  final bool failCheck;
  final bool followersLocked;
  final List<String> followed = [];

  @override
  Future<UserProfile> getProfile() async => _profile;

  @override
  Future<UserProfile> getProfileOf(String userId) async => _profile;

  @override
  Future<UserProfile> saveProfile(UserProfile value) async => _profile = value;

  @override
  Future<UserProfile> updateProfile({
    ({String? value})? bio,
    ({String? value})? avatarMediaId,
    ProfileVisibility? visibility,
    List<String>? showcasedBadges,
    ({String? value})? username,
  }) async => _profile;

  @override
  Future<List<ProfilePost>> getPosts(
    String userId, {
    ProfilePostState state = ProfilePostState.active,
  }) async => const [];

  @override
  Future<void> archivePost(String postId) async {}

  @override
  Future<void> unarchivePost(String postId) async {}

  @override
  Future<UsernameCheck> checkUsername(String username) async {
    if (failCheck) throw StateError('network');
    return const {'elif', 'ahmet'}.contains(username)
        ? const UsernameCheck(available: false, message: 'Bu kullanıcı adı alınmış.')
        : const UsernameCheck(available: true, message: 'Bu kullanıcı adı senin olabilir.');
  }

  @override
  Future<({List<FollowSummary> items, bool locked})> getFollowers(
    String userId,
  ) async => (items: const <FollowSummary>[], locked: followersLocked);

  @override
  Future<({List<FollowSummary> items, bool locked})> getFollowing(
    String userId,
  ) async => (items: const <FollowSummary>[], locked: followersLocked);

  @override
  Future<bool> follow(String userId) async {
    if (failFollow) throw StateError('network');
    followed.add(userId);
    // Sunucu takipten sonraki profili veriyor; sayaç burada da oradan geliyor.
    _profile = _profile.copyWith(
      viewerFollows: true,
      followerCount: _profile.followerCount + 1,
    );
    return true;
  }

  @override
  Future<bool> unfollow(String userId) async {
    _profile = _profile.copyWith(
      viewerFollows: false,
      followerCount: _profile.followerCount - 1,
    );
    return false;
  }

  @override
  Future<void> removeFollower(String userId) async {}
}
