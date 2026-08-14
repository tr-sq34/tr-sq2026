import '../entities/friendship.dart';

abstract interface class FriendshipRepository {
  Future<FriendshipStatus> getStatus(String userId);

  /// Gönderilen istek anında arkadaşlığa dönüşebiliyor: karşı taraf da istek
  /// göndermişse iki taraf da aynı şeyi söylemiş oluyor, ikinci bir onaya gerek
  /// kalmıyor. O yüzden dönüş değeri sabit değil, yeni durum.
  Future<FriendshipStatus> sendRequest(String userId);

  /// İsteğin kimliğiyle yanıtlanıyor, kişinin kimliğiyle değil.
  Future<FriendshipStatus> respond(String requestId, bool accepted);

  /// Kendi gönderdiğin isteği geri çekmek.
  Future<void> cancelRequest(String requestId);

  Future<void> unfriend(String userId);

  Future<void> block(String userId);

  /// Gelen ve giden bekleyen istekler bir arada.
  Future<List<FriendRequest>> getRequests();

  /// [userId] boşsa üyenin kendi listesi.
  Future<List<FriendSummary>> getFriends([String? userId]);
}
