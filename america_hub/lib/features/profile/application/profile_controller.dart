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

  Future<void> updateBio(String bio) => _mutate(() => _repository.updateProfile(bio: (value: bio.trim())));

  Future<void> updateAvatar(String mediaId) =>
      _mutate(() => _repository.updateProfile(avatarMediaId: (value: mediaId)));

  Future<void> updateVisibility(ProfileVisibility visibility) =>
      _mutate(() => _repository.updateProfile(visibility: visibility));

  /// At most three, enforced here and again by the server.
  Future<void> updateShowcase(List<String> badgeCodes) =>
      _mutate(() => _repository.updateProfile(showcasedBadges: badgeCodes.take(3).toList()));

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
