import 'dart:convert';

import '../../../../core/cache/cache_store.dart';
import '../../../auth/data/repositories/mock_auth_repository.dart';
import '../../../community/data/repositories/mock_media_upload_repository.dart';
import '../../../community/domain/entities/community_post.dart';
import '../../../community/domain/repositories/community_repository.dart';
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
    CommunityPostArchive? posts,
  }) : _auth = auth ?? MockAuthRepository(),
       _store = cacheStore ?? MemoryCacheStore(),
       _media = media,
       _posts = posts;

  final MockAuthRepository _auth;
  final CacheStore _store;

  /// Izgara artık kendi uydurduğu iki kaydı değil, üyenin gerçekten paylaştığı
  /// gönderileri gösteriyor: akışa düşen paylaşım aynı anda profilde de duruyor,
  /// fotoğraflısı da görseliyle. İki ayrı liste tutulduğu sürece üye kendi
  /// paylaşımını profilinde hiç bulamıyordu.
  final CommunityPostArchive? _posts;

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
  /// Arşiv bir kopya değil, bir işaret: paylaşımın kendisi tek yerde durur,
  /// burada yalnızca hangilerinin ızgaradan kaldırıldığı yazar. İki liste
  /// arasında kayıt taşımak, arşivlenen bir paylaşımın beğenisini ve yorumunu
  /// yolda kaybetmenin en kolay yoluydu.
  final Set<String> _archivedIds = {};

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
      username: edits['username'] as String?,
      // Başlıktaki sayı ızgaradaki kareleri sayar; arşivlenenler ikisinden de
      // düşer.
      postCount: (await getPosts(_auth.currentUserId ?? 'local-user')).length,
      followerCount: _followers.length,
      followingCount: _following.length,
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
    ({String? value})? username,
  }) async {
    final email = _auth.currentEmail ?? '';
    final edits = await _readEdits(email);
    if (bio != null) edits['bio'] = bio.value;
    if (username != null) {
      final wanted = username.value;
      // Çevrimdışı kopyada da benzersizlik var: aksi halde "alınmış" ekranını
      // hiç görmeden geliştirilen bir akış, sunucuda ilk denemede çakılır.
      if (wanted != null && _takenUsernames.contains(wanted)) {
        throw StateError('USERNAME_TAKEN');
      }
      edits['username'] = wanted;
    }
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
    final wantArchived = state == ProfilePostState.archived;
    return [
      for (final post in await _ownPosts())
        if (_archivedIds.contains(post.id) == wantArchived)
          wantArchived ? _asArchived(post) : post,
    ];
  }

  /// Üyenin kendi paylaşımları, en yenisi başta. Demo hesabın iki eski kaydı
  /// listenin sonuna ekleniyor: onlar bu hesabın geçmişi, yeni kurulan bir
  /// hesabın değil.
  Future<List<ProfilePost>> _ownPosts() async {
    final live = await _posts?.getPostsByOwner(_auth.currentUserId ?? 'local-user');
    return [
      for (final post in live ?? const <CommunityPost>[]) _asProfilePost(post),
      if (_auth.currentEmail == MockAuthRepository.demoEmail) ..._demoPosts,
    ];
  }

  /// Izgara bir görsel şeridi: paylaşımın ilk medyası varsa küçük görseli, yoksa
  /// metnin kendisi kareyi doldurur.
  ProfilePost _asProfilePost(CommunityPost post) {
    final media = post.media.isEmpty ? null : post.media.first;
    return ProfilePost(
      id: post.id,
      message: post.message,
      // Akış kaydında tarih değil, "2 sa önce" gibi bir etiket var; kimliğin
      // sonundaki damga yazıldığı anı taşıyor, o yüzden sıra ondan okunuyor.
      createdAt: _createdAtOf(post.id),
      thumbnailUrl: media?.thumbnailUrl ?? media?.url,
      likes: post.likes,
      comments: post.comments,
      archived: _archivedIds.contains(post.id),
    );
  }

  static DateTime _createdAtOf(String postId) {
    final micros = int.tryParse(postId.split('-').last);
    return micros == null || micros < 1000000
        ? DateTime.now()
        : DateTime.fromMicrosecondsSinceEpoch(micros);
  }

  ProfilePost _asArchived(ProfilePost post) => ProfilePost(
    id: post.id,
    message: post.message,
    createdAt: post.createdAt,
    thumbnailUrl: post.thumbnailUrl,
    likes: post.likes,
    comments: post.comments,
    archived: true,
  );

  @override
  Future<void> archivePost(String postId) async => _archivedIds.add(postId);

  @override
  Future<void> unarchivePost(String postId) async => _archivedIds.remove(postId);

  /// Sunucuda benzersizliği indeks garanti ediyor; burada bir avuç ad, "bu
  /// alınmış" yolunun da çalıştığını görebilmek için.
  static const _takenUsernames = {'ahmet', 'elif', 'turksquare_resmi'};

  /// Kimin kimi takip ettiği. Demo hesabın iki takipçisi ve bir takip ettiği
  /// var; yeni kurulan bir hesabın hiçbiri yok, çünkü kimse onu tanımıyor.
  final List<FollowSummary> _followers = [
    const FollowSummary(
      userId: 'member-elif',
      displayName: 'Elif Demir',
      username: 'elif',
      city: 'Paterson',
      regionCode: 'NJ',
    ),
    const FollowSummary(
      userId: 'member-mert',
      displayName: 'Mert Kaya',
      username: 'mertkaya',
      city: 'Brooklyn',
      regionCode: 'NY',
      viewerFollows: true,
    ),
  ];

  final List<FollowSummary> _following = [
    const FollowSummary(
      userId: 'member-mert',
      displayName: 'Mert Kaya',
      username: 'mertkaya',
      city: 'Brooklyn',
      regionCode: 'NY',
      viewerFollows: true,
    ),
  ];

  @override
  Future<UsernameCheck> checkUsername(String username) async {
    final value = username.trim().toLowerCase();
    if (value.length < 3 || value.length > 24) {
      return const UsernameCheck(
        available: false,
        message: 'Kullanıcı adı 3-24 karakter olmalı.',
      );
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9_.]{1,22}[a-z0-9]$').hasMatch(value) ||
        value.contains('..')) {
      return const UsernameCheck(
        available: false,
        message: 'Yalnızca küçük harf, rakam, alt çizgi ve nokta kullanabilirsin.',
      );
    }
    return _takenUsernames.contains(value)
        ? const UsernameCheck(available: false, message: 'Bu kullanıcı adı alınmış.')
        : const UsernameCheck(available: true, message: 'Bu kullanıcı adı senin olabilir.');
  }

  @override
  Future<({List<FollowSummary> items, bool locked})> getFollowers(String userId) async =>
      (items: List.of(_followers), locked: false);

  @override
  Future<({List<FollowSummary> items, bool locked})> getFollowing(String userId) async =>
      (items: List.of(_following), locked: false);

  @override
  Future<bool> follow(String userId) async {
    if (_following.any((item) => item.userId == userId)) return true;
    final known = _followers.where((item) => item.userId == userId);
    _following.add(
      (known.isEmpty
              ? FollowSummary(userId: userId, displayName: 'TurkSquare üyesi')
              : known.first)
          .copyWith(viewerFollows: true),
    );
    _markViewerFollows(userId, true);
    return true;
  }

  @override
  Future<bool> unfollow(String userId) async {
    _following.removeWhere((item) => item.userId == userId);
    _markViewerFollows(userId, false);
    return false;
  }

  @override
  Future<void> removeFollower(String userId) async =>
      _followers.removeWhere((item) => item.userId == userId);

  void _markViewerFollows(String userId, bool value) {
    for (var index = 0; index < _followers.length; index++) {
      if (_followers[index].userId == userId) {
        _followers[index] = _followers[index].copyWith(viewerFollows: value);
      }
    }
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
