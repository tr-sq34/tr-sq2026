import 'package:flutter/foundation.dart';

import '../../../core/state/async_state.dart';
import '../domain/entities/user_profile.dart';
import '../domain/repositories/profile_repository.dart';

class ProfileController extends ChangeNotifier {
  ProfileController({required ProfileRepository repository}) : _repository = repository;

  final ProfileRepository _repository;
  AsyncState<UserProfile> _state = const AsyncLoading();
  AsyncState<UserProfile> get state => _state;
  bool _isSaving = false;
  bool get isSaving => _isSaving;

  Future<void> load() async {
    _state = const AsyncLoading();
    notifyListeners();
    try {
      _state = AsyncData(await _repository.getProfile());
    } catch (_) {
      _state = const AsyncFailure('We could not load your profile.');
    }
    notifyListeners();
  }

  Future<void> save({required String name, required String city, required String state, required List<String> interests, required ProfileVisibility visibility}) async {
    final current = _state;
    if (current is! AsyncData<UserProfile>) return;
    _isSaving = true;
    notifyListeners();
    try {
      final updated = current.value.copyWith(
        displayName: name.trim(),
        city: city.trim(),
        state: state.trim(),
        interests: interests,
        visibility: visibility,
        isOnboardingComplete: true,
      );
      _state = AsyncData(await _repository.saveProfile(updated));
    } catch (_) {
      _state = const AsyncFailure('We could not save your profile.');
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }
}
