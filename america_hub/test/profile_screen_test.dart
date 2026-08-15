import 'package:america_hub/features/profile/application/friendship_controller.dart';
import 'package:america_hub/features/profile/data/repositories/mock_friendship_repository.dart';
import 'package:america_hub/features/profile/domain/entities/friendship.dart';
import 'package:america_hub/features/profile/domain/repositories/friendship_repository.dart';
import 'package:america_hub/core/network/api_client.dart';
import 'package:america_hub/core/storage/in_memory_token_store.dart';
import 'package:america_hub/features/community/application/media_upload_controller.dart';
import 'package:america_hub/features/community/application/story_controller.dart';
import 'package:america_hub/features/community/data/repositories/mock_community_repository.dart';
import 'package:america_hub/features/community/data/repositories/mock_media_upload_repository.dart';
import 'package:america_hub/features/journey/application/journey_controller.dart';
import 'package:america_hub/features/journey/data/repositories/mock_journey_repository.dart';
import 'package:america_hub/features/journey/presentation/screens/journey_screen.dart';
import 'package:america_hub/features/profile/application/profile_controller.dart';
import 'package:america_hub/features/profile/domain/entities/user_profile.dart';
import 'package:america_hub/features/profile/domain/repositories/profile_repository.dart';
import 'package:america_hub/features/profile/presentation/screens/profile_screen.dart';
import 'package:america_hub/features/verification/application/member_capabilities_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_image_http.dart';

const _base = UserProfile(
  id: 'me',
  displayName: 'Alican Argınç',
  email: '',
  city: 'Paterson',
  state: 'NJ',
  isOnboardingComplete: true,
);

/// A profile repository the test can dictate, so each case describes exactly
/// one member rather than leaning on whatever the mock happens to hold.
class _FakeProfileRepository implements ProfileRepository {
  _FakeProfileRepository(this.profile, {this.posts = const []});

  UserProfile profile;
  List<ProfilePost> posts;
  List<ProfilePost> archived = const [];
  final List<String> archiveCalls = [];

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
  }) async => profile = profile.copyWith(
    bio: bio?.value ?? profile.bio,
    username: username?.value ?? profile.username,
  );

  /// Takip tarafı bu testlerde kullanılmıyor; boş liste dönmek yerine "kilitli
  /// değil, gerçekten boş" diyor ki bir gün kullanılırsa yalan söylemesin.
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
  }) async => state == ProfilePostState.archived ? archived : posts;

  @override
  Future<void> archivePost(String postId) async {
    archiveCalls.add(postId);
    final post = posts.firstWhere((item) => item.id == postId);
    posts = posts.where((item) => item.id != postId).toList();
    archived = [
      ProfilePost(
        id: post.id,
        message: post.message,
        createdAt: post.createdAt,
        archived: true,
      ),
      ...archived,
    ];
  }

  @override
  Future<void> unarchivePost(String postId) async {}
}

/// Arkadaşlık deposu: gelen kutusunu ve listeyi testin dikte ettiği hâliyle
/// verir, yanıtları kaydeder.
class _FakeFriendships implements FriendshipRepository {
  _FakeFriendships({this.requests = const []});

  List<FriendRequest> requests;
  List<FriendSummary> friends = const [];
  final List<String> answers = [];

  @override
  Future<FriendshipStatus> getStatus(String userId) async =>
      FriendshipStatus.none;

  @override
  Future<FriendshipStatus> sendRequest(String userId) async =>
      FriendshipStatus.pendingOutgoing;

  @override
  Future<FriendshipStatus> respond(String requestId, bool accepted) async {
    answers.add('$requestId:$accepted');
    final request = requests.firstWhere((item) => item.id == requestId);
    requests = requests.where((item) => item.id != requestId).toList();
    if (accepted) {
      friends = [
        ...friends,
        FriendSummary(
          userId: request.userId,
          displayName: request.displayName,
          city: 'Paterson',
          regionCode: 'NJ',
        ),
      ];
    }
    return accepted ? FriendshipStatus.friends : FriendshipStatus.none;
  }

  @override
  Future<void> cancelRequest(String requestId) async {}

  @override
  Future<void> unfriend(String userId) async {}

  @override
  Future<void> block(String userId) async {}

  @override
  Future<List<FriendRequest>> getRequests() async => List.of(requests);

  @override
  Future<List<FriendSummary>> getFriends([String? userId]) async =>
      List.of(friends);
}

class _StubCapabilities extends MemberCapabilitiesController {
  _StubCapabilities(ApiClient client) : super(client, client);

  @override
  Future<void> load() async {}
}

Future<_FakeProfileRepository> _pumpProfile(
  WidgetTester tester,
  UserProfile profile, {
  List<ProfilePost> posts = const [],
  FriendshipRepository? friendships,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  installFakeImageHttp();

  final repository = _FakeProfileRepository(profile, posts: posts);
  final apiClient = ApiClient(tokenStore: InMemoryTokenStore());
  final community = MockCommunityRepository();

  await tester.pumpWidget(
    MaterialApp(
      home: ProfileScreen(
        controller: ProfileController(repository: repository),
        friendshipController: FriendshipController(
          repository: friendships ?? MockFriendshipRepository(),
        ),
        journeyController: JourneyController(repository: const MockJourneyRepository()),
        onSignOut: () async {},
        memberCapabilitiesController: _StubCapabilities(apiClient),
        storyController: StoryController(repository: community),
        mediaUploadController: MediaUploadController(
          repository: MockMediaUploadRepository(),
        ),
        postCommands: community,
      ),
    ),
  );
  // Bounded pumps rather than pumpAndSettle: the level ring and the loading
  // spinners animate forever, so settling never returns.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
  return repository;
}

void main() {
  testWidgets('the tabs read Profil, Paylaşımlar, Arkadaşlar in that order', (tester) async {
    await _pumpProfile(tester, _base);

    final tabs = tester.widgetList<Tab>(find.byType(Tab)).toList();
    expect(tabs.map((tab) => tab.text).toList(), ['Profil', 'Paylaşımlar', 'Arkadaşlar']);
  });

  testWidgets('a member who has told us where they came from sees the journey', (tester) async {
    await _pumpProfile(
      tester,
      _base.copyWith(originCity: 'İzmir', originCountry: 'TR'),
    );

    expect(find.text('İzmir, TR ➜ Paterson, NJ'), findsWidgets);
  });

  testWidgets('a missing origin asks for it instead of inventing one', (tester) async {
    await _pumpProfile(tester, _base);

    expect(find.textContaining('İzmir'), findsNothing);
    expect(find.textContaining('kurulum ekranından ekleyebilirsin'), findsOneWidget);
  });

  testWidgets('the facts are lines on one surface, not a card each', (tester) async {
    await _pumpProfile(
      tester,
      _base.copyWith(
        originCity: 'İzmir',
        originCountry: 'TR',
        interests: const ['yemek', 'futbol', 'göçmenlik'],
      ),
    );

    // Every fact used to open its own padded card, so three short answers ate
    // most of the screen. Labelled rows now, and the interests are one line
    // instead of a pile of chips.
    expect(find.text('Nerelisin'), findsOneWidget);
    expect(find.text('İlgi alanları'), findsOneWidget);
    expect(find.text('yemek, futbol, göçmenlik'), findsOneWidget);
    expect(find.byType(Chip), findsNothing);
  });

  testWidgets('the avatar draws the photo it was given', (tester) async {
    await _pumpProfile(
      tester,
      _base.copyWith(avatarUrl: 'https://cdn.example.com/avatar.png'),
    );

    expect(find.byType(Image), findsWidgets);
    expect(find.text('AA'), findsNothing);
  });

  testWidgets('an address nothing can draw keeps the initials', (tester) async {
    // A bare upload id is neither a URL nor a path. It used to be handed to
    // Image.network, which failed silently while the non-empty value hid the
    // initials — the circle simply went blank and the photo looked unsaved.
    await _pumpProfile(tester, _base.copyWith(avatarUrl: 'media-abc123'));

    expect(find.text('AA'), findsOneWidget);
  });

  testWidgets('the badge counter is a way in, not a decoration', (tester) async {
    await _pumpProfile(tester, _base);

    await tester.tap(find.text('Rozet'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.byType(JourneyScreen), findsOneWidget);
    expect(find.widgetWithText(Tab, 'Rozetler'), findsOneWidget);
  });

  testWidgets('long-pressing a post in the grid offers archive and delete', (tester) async {
    final repository = await _pumpProfile(
      tester,
      _base,
      posts: [
        ProfilePost(
          id: 'post-1',
          message: 'Paterson\'da yeni fırın',
          createdAt: DateTime(2026, 7, 2),
        ),
      ],
    );

    await tester.tap(find.widgetWithText(Tab, 'Paylaşımlar'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    // The header scrolls away first: NestedScrollView lays the grid out below
    // the fold, where a long press lands on the outer viewport instead.
    await tester.dragFrom(const Offset(180, 700), const Offset(0, -400));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.longPress(find.textContaining('Paterson\'da yeni fırın'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('Arşivle'), findsOneWidget);
    expect(find.text('Sil'), findsOneWidget);

    await tester.tap(find.text('Arşivle'));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    // Archiving is not deleting: the post leaves the grid but the repository
    // still holds it, ready for the Arşiv segment.
    expect(repository.archiveCalls, ['post-1']);
    expect(repository.archived.single.id, 'post-1');
    expect(find.textContaining('Paterson\'da yeni fırın'), findsNothing);
  });

  testWidgets('the friends tab locks rather than listing made-up names', (tester) async {
    await _pumpProfile(
      tester,
      _base.copyWith(isSelf: false, canViewFullProfile: false),
    );

    await tester.tap(find.text('Arkadaşlar'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(find.text('Bu profil gizli'), findsOneWidget);
    expect(find.text('Elif Demir'), findsNothing);
  });

  testWidgets('gelen istek yanitlanabiliyor ve listeye donusuyor', (
    tester,
  ) async {
    final friendships = _FakeFriendships(
      requests: [
        FriendRequest(
          id: 'r1',
          userId: 'member-1',
          displayName: 'Elif Demir',
          createdAt: DateTime(2026, 8, 13),
          isIncoming: true,
        ),
      ],
    );
    await _pumpProfile(tester, _base, friendships: friendships);

    await tester.tap(find.text('Arkadaşlar'));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('Gelen istekler'), findsOneWidget);
    expect(find.text('Elif Demir'), findsOneWidget);

    // NestedScrollView icindeki dokunma noktasi testte govdeye degil basliga
    // dusuyor; dugmenin kendi geri cagrisi cagriliyor.
    tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'Kabul et'))
        .onPressed!();
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 60));
    }

    expect(friendships.answers, ['r1:true']);
    expect(find.text('Gelen istekler'), findsNothing);
    expect(find.text('Arkadaşlar (1)'), findsOneWidget);
    expect(find.widgetWithText(ListTile, 'Elif Demir'), findsOneWidget);
  });
}
