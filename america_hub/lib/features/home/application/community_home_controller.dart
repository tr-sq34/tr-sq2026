import 'package:flutter/foundation.dart';

import '../data/community_home_repository.dart';

class CommunityHomeController extends ChangeNotifier {
  CommunityHomeController(this._repository);
  final CommunityHomeRepository _repository;
  CommunityHomeSummary? _summary;
  bool _loading = false;
  String? _error;
  CommunityHomeSummary? get summary => _summary;
  bool get loading => _loading;
  String? get error => _error;

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    // Screens start this from `initState`, i.e. while the tree is still being
    // built, and a listener that is already on screen — the shell's top bar
    // reads the locality from here — cannot be marked dirty during a build.
    // The flag above is set synchronously so the in-flight guard still holds;
    // only the notification waits for the current frame to finish.
    await Future<void>.microtask(() {});
    notifyListeners();
    try {
      _summary = await _repository.fetch();
    } catch (_) {
      _error = 'Ana sayfa bilgileri yüklenemedi.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }
}
