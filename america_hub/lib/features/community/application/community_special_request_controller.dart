import 'package:flutter/foundation.dart';

import '../domain/entities/community_special_request.dart';
import '../domain/repositories/community_special_request_repository.dart';

class CommunitySpecialRequestController extends ChangeNotifier {
  CommunitySpecialRequestController({required CommunitySpecialRequestRepository repository}) : _repository = repository;

  final CommunitySpecialRequestRepository _repository;
  final Map<String, List<CommunitySpecialRequest>> _byPost = {};
  bool isSubmitting = false;
  String? errorMessage;

  List<CommunitySpecialRequest> requestsFor(String postId) => _byPost[postId] ?? const [];

  Future<void> loadForPost(String postId) async {
    _byPost[postId] = await _repository.getRequestsForPost(postId);
    notifyListeners();
  }

  Future<bool> send({required String postId, required CommunitySpecialRequestType type, required String message}) async {
    final normalized = message.trim();
    if (normalized.isEmpty || normalized.length > 500) {
      errorMessage = 'Mesaj 1–500 karakter arasında olmalı.';
      notifyListeners();
      return false;
    }
    isSubmitting = true;
    errorMessage = null;
    notifyListeners();
    try {
      final request = await _repository.createRequest(postId: postId, type: type, message: normalized);
      _byPost[postId] = [request, ...requestsFor(postId)];
      return true;
    } catch (_) {
      errorMessage = 'İstek şu anda gönderilemedi. Lütfen tekrar deneyin.';
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  Future<void> updateStatus(String requestId, CommunitySpecialRequestStatus status) async {
    await _repository.updateStatus(requestId, status);
    for (final entry in _byPost.entries) {
      final index = entry.value.indexWhere((item) => item.id == requestId);
      if (index < 0) continue;
      final previous = entry.value[index];
      entry.value[index] = CommunitySpecialRequest(
        id: previous.id, postId: previous.postId, type: previous.type, senderId: previous.senderId,
        message: previous.message, createdAt: previous.createdAt, status: status,
      );
      notifyListeners();
      return;
    }
  }
}
