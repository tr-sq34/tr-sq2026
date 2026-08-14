enum FriendshipStatus { none, pendingIncoming, pendingOutgoing, friends, blocked }

class Friendship {
  const Friendship({required this.userId, required this.status});
  final String userId;
  final FriendshipStatus status;
}

/// Bekleyen bir arkadaşlık isteği.
///
/// Yanıtlanırken isteğin kendi kimliği kullanılıyor, karşı tarafın kimliği
/// değil: aynı iki kişi arasında iki yönde iki ayrı istek olabiliyor ve
/// "kabul et" bunlardan hangisini kastettiğini bilmek zorunda.
class FriendRequest {
  const FriendRequest({
    required this.id,
    required this.userId,
    required this.displayName,
    required this.createdAt,
    required this.isIncoming,
    this.avatarUrl,
  });

  final String id;
  final String userId;
  final String displayName;
  final DateTime createdAt;

  /// Gelen istek yanıtlanıyor, giden istek geri çekiliyor. Tek ekranda iki
  /// farklı düğme demek.
  final bool isIncoming;
  final String? avatarUrl;
}

/// Arkadaş listesindeki bir kişi.
class FriendSummary {
  const FriendSummary({
    required this.userId,
    required this.displayName,
    this.city,
    this.regionCode,
    this.avatarUrl,
  });

  final String userId;
  final String displayName;
  final String? city;
  final String? regionCode;
  final String? avatarUrl;

  String get placeLabel => [
    if (city != null && city!.isNotEmpty) city!,
    if (regionCode != null && regionCode!.isNotEmpty) regionCode!,
  ].join(', ');
}
