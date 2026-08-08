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
