import 'package:flutter/foundation.dart';

import '../domain/entities/friendship.dart';
import '../domain/repositories/friendship_repository.dart';

class FriendshipController extends ChangeNotifier {
  FriendshipController({required FriendshipRepository repository})
    : _repository = repository;

  final FriendshipRepository _repository;
  final Map<String, FriendshipStatus> _statuses = {};

  List<FriendRequest> requests = const [];
  List<FriendSummary> friends = const [];
  bool isLoading = false;
  bool hasLoaded = false;
  String? errorMessage;

  List<FriendRequest> get incomingRequests =>
      requests.where((request) => request.isIncoming).toList(growable: false);
  List<FriendRequest> get outgoingRequests =>
      requests.where((request) => !request.isIncoming).toList(growable: false);

  /// Önce bilinen durum, sonra yüklenmiş listeler. Liste zaten okunmuşsa
  /// aynı bilgi için üye başına ayrı bir istek atmanın anlamı yok.
  FriendshipStatus statusOf(String userId) {
    final known = _statuses[userId];
    if (known != null) return known;
    if (friends.any((friend) => friend.userId == userId)) {
      return FriendshipStatus.friends;
    }
    for (final request in requests) {
      if (request.userId != userId) continue;
      return request.isIncoming
          ? FriendshipStatus.pendingIncoming
          : FriendshipStatus.pendingOutgoing;
    }
    return FriendshipStatus.none;
  }

  /// Gelen kutusu ve liste birlikte okunuyor: ikisi de aynı ekranda duruyor ve
  /// bir isteği kabul etmek ikisini birden değiştiriyor.
  Future<void> load() async {
    if (isLoading) return;
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final results = await Future.wait([
        _repository.getRequests(),
        _repository.getFriends(),
      ]);
      requests = results[0] as List<FriendRequest>;
      friends = results[1] as List<FriendSummary>;
      hasLoaded = true;
    } catch (_) {
      errorMessage = 'Arkadaş listesi şu anda yüklenemedi.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadStatus(String userId) async {
    try {
      _statuses[userId] = await _repository.getStatus(userId);
      notifyListeners();
    } catch (_) {
      // Durum okunamadıysa bilinen bir şey yok; ekran "istek gönder" gösterir.
    }
  }

  /// Karşı taraf da istek göndermişse sunucu bunu doğrudan arkadaşlığa
  /// çeviriyor. O yüzden gelen durum olduğu gibi yazılıyor, "beklemede" diye
  /// varsayılmıyor.
  Future<bool> send(String userId) async {
    try {
      _statuses[userId] = await _repository.sendRequest(userId);
    } catch (_) {
      errorMessage = 'İstek şu anda gönderilemedi.';
      notifyListeners();
      return false;
    }
    errorMessage = null;
    await _refreshQuietly();
    return true;
  }

  Future<bool> respond(String requestId, bool accepted) async {
    final request = _findRequest(requestId);
    try {
      final status = await _repository.respond(requestId, accepted);
      if (request != null) _statuses[request.userId] = status;
    } catch (_) {
      errorMessage = 'İstek şu anda yanıtlanamadı.';
      notifyListeners();
      return false;
    }
    errorMessage = null;
    requests = requests
        .where((item) => item.id != requestId)
        .toList(growable: false);
    notifyListeners();
    // Kabul edilen istek listeye yeni bir kişi ekliyor; listeyi sunucudan
    // okumak, adı ve şehri uydurmaktan iyi.
    if (accepted) await _refreshQuietly();
    return true;
  }

  Future<bool> cancelRequest(String requestId) async {
    final request = _findRequest(requestId);
    try {
      await _repository.cancelRequest(requestId);
    } catch (_) {
      errorMessage = 'İstek şu anda geri çekilemedi.';
      notifyListeners();
      return false;
    }
    errorMessage = null;
    if (request != null) _statuses[request.userId] = FriendshipStatus.none;
    requests = requests
        .where((item) => item.id != requestId)
        .toList(growable: false);
    notifyListeners();
    return true;
  }

  Future<bool> unfriend(String userId) async {
    try {
      await _repository.unfriend(userId);
    } catch (_) {
      errorMessage = 'Arkadaşlık şu anda kaldırılamadı.';
      notifyListeners();
      return false;
    }
    errorMessage = null;
    _statuses[userId] = FriendshipStatus.none;
    friends = friends
        .where((item) => item.userId != userId)
        .toList(growable: false);
    notifyListeners();
    return true;
  }

  Future<bool> block(String userId) async {
    try {
      await _repository.block(userId);
    } catch (_) {
      errorMessage = 'Üye şu anda engellenemedi.';
      notifyListeners();
      return false;
    }
    errorMessage = null;
    _statuses[userId] = FriendshipStatus.blocked;
    friends = friends
        .where((item) => item.userId != userId)
        .toList(growable: false);
    requests = requests
        .where((item) => item.userId != userId)
        .toList(growable: false);
    notifyListeners();
    return true;
  }

  /// Bir üyeyle arasındaki bekleyen istek.
  ///
  /// Profil ekranı isteğe yanıt verebilmek için kimliğini bilmek zorunda ve
  /// elindeki tek şey üyenin kimliği. `null` dönmesi "istek yok" demek değil,
  /// "liste okunmamış ya da okunamamış" da olabilir; çağıran taraf ikisini
  /// ayırt edebilsin diye [hasLoaded] ayrı duruyor.
  FriendRequest? requestWith(String userId) {
    for (final request in requests) {
      if (request.userId == userId) return request;
    }
    return null;
  }

  FriendRequest? _findRequest(String requestId) {
    for (final request in requests) {
      if (request.id == requestId) return request;
    }
    return null;
  }

  /// Sessiz tazeleme: hata mesajı basmıyor, çünkü asıl işlem zaten başarılı
  /// oldu; sadece ekrandaki liste bir adım geriden gelir.
  Future<void> _refreshQuietly() async {
    try {
      final results = await Future.wait([
        _repository.getRequests(),
        _repository.getFriends(),
      ]);
      requests = results[0] as List<FriendRequest>;
      friends = results[1] as List<FriendSummary>;
      hasLoaded = true;
    } catch (_) {
      // yoksay
    }
    notifyListeners();
  }
}
