import 'package:flutter/foundation.dart';

import '../../../core/state/async_state.dart';
import '../domain/entities/community_post.dart';
import '../domain/repositories/community_repository.dart';

class ProfilePostsController extends ChangeNotifier {
  ProfilePostsController({required CommunityPostArchive archive}) : _archive = archive;

  final CommunityPostArchive _archive;
  AsyncState<List<CommunityPost>> _state = const AsyncLoading();
  AsyncState<List<CommunityPost>> get state => _state;

  Future<void> load(String ownerId) async {
    _state = const AsyncLoading();
    notifyListeners();
    try {
      _state = AsyncData(await _archive.getPostsByOwner(ownerId));
    } catch (_) {
      _state = const AsyncFailure('Paylaşımlar yüklenemedi.');
    }
    notifyListeners();
  }
}
