import 'package:flutter/foundation.dart';

import '../domain/entities/community_special_request.dart';
import '../domain/repositories/community_special_request_repository.dart';

class CommunitySpecialRequestController extends ChangeNotifier {
  CommunitySpecialRequestController({required CommunitySpecialRequestRepository repository}) : _repository = repository;

  final CommunitySpecialRequestRepository _repository;
  final Map<String, List<CommunitySpecialRequest>> _byPost = {};
  final Set<String> _loading = {};
  bool isSubmitting = false;
  String? errorMessage;

  List<CommunitySpecialRequest> requestsFor(String postId) => _byPost[postId] ?? const [];

  /// Liste daha hiç okunmadıysa "istek yok" ile "henüz bilmiyoruz" aynı şey
  /// değil: sahibine boş bir liste göstermeden önce cevabın geldiğini bilmemiz
  /// gerekiyor.
  bool isLoading(String postId) => _loading.contains(postId);
  bool hasLoaded(String postId) => _byPost.containsKey(postId);

  Future<void> loadForPost(String postId) async {
    if (_loading.contains(postId)) return;
    _loading.add(postId);
    errorMessage = null;
    notifyListeners();
    try {
      _byPost[postId] = await _repository.getRequestsForPost(postId);
    } catch (_) {
      errorMessage = 'İstekler şu anda yüklenemedi.';
    } finally {
      _loading.remove(postId);
      notifyListeners();
    }
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

  /// Yanıt sunucuda tutmazsa listede de tutmuyor: kabul edilmiş görünüp
  /// karşı tarafa hiç ulaşmamış bir istek, en kötü sonuç.
  Future<bool> updateStatus(String requestId, CommunitySpecialRequestStatus status) async {
    try {
      await _repository.updateStatus(requestId, status);
    } catch (_) {
      errorMessage = 'İstek şu anda güncellenemedi.';
      notifyListeners();
      return false;
    }
    errorMessage = null;
    for (final entry in _byPost.entries) {
      final index = entry.value.indexWhere((item) => item.id == requestId);
      if (index < 0) continue;
      entry.value[index] = entry.value[index].copyWith(status: status);
      break;
    }
    notifyListeners();
    return true;
  }
}
