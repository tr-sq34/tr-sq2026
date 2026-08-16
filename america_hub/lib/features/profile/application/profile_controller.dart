import 'package:flutter/foundation.dart';

import '../../../core/state/async_state.dart';
import '../domain/entities/user_profile.dart';
import '../domain/repositories/profile_repository.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({required ProfileRepository repository}) : _repository = repository;

  final ProfileRepository _repository;

  AsyncState<UserProfile> _state = const AsyncLoading();
  AsyncState<UserProfile> get state => _state;

  AsyncState<List<ProfilePost>> _posts = const AsyncLoading();
  AsyncState<List<ProfilePost>> get posts => _posts;

  AsyncState<List<ProfilePost>> _archived = const AsyncLoading();
  AsyncState<List<ProfilePost>> get archived => _archived;

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  Future<void> load() async {
    _state = const AsyncLoading();
    notifyListeners();
    try {
      final profile = await _repository.getProfile();
      _state = AsyncData(profile);
      notifyListeners();
      await loadPosts(profile.id);
    } catch (_) {
      _state = const AsyncFailure('Profilin yüklenemedi.');
      notifyListeners();
    }
  }

  Future<void> loadPosts(String ownerId) async {
    try {
      _posts = AsyncData(await _repository.getPosts(ownerId));
    } catch (_) {
      _posts = const AsyncFailure('Paylaşımlar yüklenemedi.');
    }
    notifyListeners();
  }

  /// Loaded on demand: the archive is a tab the member has to open, and it is
  /// visible to nobody else, so there is no reason to fetch it up front.
  Future<void> loadArchived(String ownerId) async {
    _archived = const AsyncLoading();
    notifyListeners();
    try {
      _archived = AsyncData(
        await _repository.getPosts(ownerId, state: ProfilePostState.archived),
      );
    } catch (_) {
      _archived = const AsyncFailure('Arşiv yüklenemedi.');
    }
    notifyListeners();
  }

  Future<void> archivePost(String postId) async {
    final profile = _state;
    if (profile is! AsyncData<UserProfile>) return;
    await _repository.archivePost(postId);
    // Both lists are re-read rather than patched in place: the post count on the
    // header comes from the server too, and a hand-moved item would leave the
    // two disagreeing.
    await loadPosts(profile.value.id);
    await loadArchived(profile.value.id);
  }

  Future<void> unarchivePost(String postId) async {
    final profile = _state;
    if (profile is! AsyncData<UserProfile>) return;
    await _repository.unarchivePost(postId);
    await loadPosts(profile.value.id);
    await loadArchived(profile.value.id);
  }

  /// Başa sabitle / sabiti kaldır. Null dönerse istek gitmedi ya da sunucu
  /// reddetti; ekran nedenini yazıyor ve kart eski hâlinde kalıyor.
  Future<String?> setPinned(String postId, bool pinned) async {
    final profile = _state;
    if (profile is! AsyncData<UserProfile>) return 'Profil henüz yüklenmedi.';
    try {
      final result = await _repository.setPostSettings(postId, pinned: pinned);
      if (result.pinned != pinned) {
        return 'En fazla 3 paylaşım sabitlenebilir. Önce birinin sabitini kaldır.';
      }
    } catch (error) {
      return '$error'.contains('PIN_LIMIT_REACHED')
          ? 'En fazla 3 paylaşım sabitlenebilir. Önce birinin sabitini kaldır.'
          : 'Paylaşım sabitlenemedi.';
    }
    // Sıralamayı sunucu yapıyor; listeyi elde yeniden dizmek, ızgaranın
    // sunucudakinden farklı görünmesine giden ilk adım olurdu.
    await loadPosts(profile.value.id);
    return null;
  }

  Future<String?> setCommentsEnabled(String postId, bool enabled) async {
    final profile = _state;
    if (profile is! AsyncData<UserProfile>) return 'Profil henüz yüklenmedi.';
    try {
      await _repository.setPostSettings(postId, commentsEnabled: enabled);
    } catch (_) {
      return enabled ? 'Yorumlar açılamadı.' : 'Yorumlar kapatılamadı.';
    }
    await loadPosts(profile.value.id);
    return null;
  }

  Future<void> updateBio(String bio) => _mutate(() => _repository.updateProfile(bio: (value: bio.trim())));

  Future<void> updateAvatar(String mediaId) =>
      _mutate(() => _repository.updateProfile(avatarMediaId: (value: mediaId)));

  Future<void> updateVisibility(ProfileVisibility visibility) =>
      _mutate(() => _repository.updateProfile(visibility: visibility));

  /// At most three, enforced here and again by the server.
  Future<void> updateShowcase(List<String> badgeCodes) =>
      _mutate(() => _repository.updateProfile(showcasedBadges: badgeCodes.take(3).toList()));

  /// Üye yazarken sorulan soru. Yalnızca okuma yaptığı için `_mutate`'ten
  /// geçmiyor: bir denetimin başarısız olması profili hata durumuna düşürmemeli.
  Future<UsernameCheck> checkUsername(String username) async {
    try {
      return await _repository.checkUsername(username);
    } catch (_) {
      // Bir cevap alamadıysak "müsait" demiyoruz. Boş bir onay, kaydetme anında
      // reddedilecek bir adı üyeye kabul edilmiş gibi göstermek olurdu.
      return const UsernameCheck(
        available: false,
        message: 'Kullanıcı adı şu anda denetlenemedi.',
      );
    }
  }

  /// Kullanıcı adını kaydetmek. Başarısızlığın nedeni ekranda yazılacağı için
  /// `_mutate`'in sessiz hata durumuna düşmüyor; profil yerinde kalıyor.
  Future<String?> saveUsername(String? username) async {
    if (_state is! AsyncData<UserProfile>) return 'Profil henüz yüklenmedi.';
    _isSaving = true;
    notifyListeners();
    try {
      _state = AsyncData(
        await _repository.updateProfile(username: (value: username)),
      );
      return null;
    } catch (error) {
      return '$error'.contains('USERNAME_TAKEN')
          ? 'Bu kullanıcı adı az önce alındı. Başka bir tane dene.'
          : 'Kullanıcı adı kaydedilemedi.';
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  /// Başka bir üyenin profili. Denetleyicinin kendi durumuna dokunmuyor: bu
  /// ekran açıkken üyenin kendi profili hâlâ arkada duruyor ve geri dönüldüğünde
  /// yeniden yüklenmesi gerekmemeli.
  Future<UserProfile> profileOf(String userId) => _repository.getProfileOf(userId);

  /// Başka bir üyenin paylaşımları. `loadPosts` gibi denetleyicide saklanmıyor:
  /// saklasaydı bir başkasının ızgarası, geri dönüldüğünde üyenin kendi
  /// profilinde duruyor olurdu.
  Future<List<ProfilePost>> postsOf(String userId) => _repository.getPosts(userId);

  Future<({List<FollowSummary> items, bool locked})> followers(String userId) =>
      _repository.getFollowers(userId);

  Future<({List<FollowSummary> items, bool locked})> following(String userId) =>
      _repository.getFollowing(userId);

  /// Takip et / takipten çık. Dönen değer işlemden sonraki durum; null ise
  /// istek gitmedi ve ekran düğmeyi eski haline bırakmalı.
  Future<bool?> setFollowing(String userId, bool follow) async {
    try {
      final result =
          follow ? await _repository.follow(userId) : await _repository.unfollow(userId);
      // Sayaç sunucudan yeniden okunuyor: burada birer artırmak, arkadaşlık
      // yüzünden takipten çıkmanın işlemediği durumda yanlış sayı gösterirdi.
      if (_state is AsyncData<UserProfile>) await load();
      return result;
    } catch (_) {
      return null;
    }
  }

  Future<bool> removeFollower(String userId) async {
    try {
      await _repository.removeFollower(userId);
      await load();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> save({
    required String name,
    required String city,
    required String state,
    required List<String> interests,
    required ProfileVisibility visibility,
  }) async {
    final current = _state;
    if (current is! AsyncData<UserProfile>) return;
    await _mutate(() => _repository.saveProfile(
      current.value.copyWith(
        displayName: name.trim(),
        city: city.trim(),
        state: state.trim(),
        interests: interests,
        visibility: visibility,
        isOnboardingComplete: true,
      ),
    ));
  }

  Future<void> _mutate(Future<UserProfile> Function() write) async {
    if (_state is! AsyncData<UserProfile>) return;
    _isSaving = true;
    notifyListeners();
    try {
      _state = AsyncData(await write());
    } catch (_) {
      _state = const AsyncFailure('Profilin kaydedilemedi.');
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
