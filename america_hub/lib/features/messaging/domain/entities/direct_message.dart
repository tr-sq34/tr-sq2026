/// Delivery state of a message as far as this device knows.
///
/// [sending] and [failed] only ever describe a message this device just
/// composed. Anything that came back from the gateway is [sent] by definition.
enum DirectMessageStatus { sending, sent, failed }

class DirectMessage {
  const DirectMessage({
    required this.id,
    required this.senderId,
    required this.body,
    required this.sentAt,
    this.status = DirectMessageStatus.sent,
    this.senderName,
  });

  /// The gateway's message ID. While a message is still [DirectMessageStatus.sending]
  /// this is the idempotency key the client generated, which is also what makes
  /// a retry safe: the same key never produces a second message.
  final String id;

  /// A TurkSquare user ID. The gateway translates the transport's own sender
  /// identifiers before they reach this app.
  final String senderId;
  final String body;
  final DateTime sentAt;
  final DirectMessageStatus status;

  /// Sent only for group threads, where a bubble has to name its author. Null
  /// in a direct thread, and also in a group when the sender's profile has not
  /// reached the messaging projection yet.
  final String? senderName;

  bool isMine(String viewerId) => senderId == viewerId;

  DirectMessage copyWith({String? id, DirectMessageStatus? status}) =>
      DirectMessage(
        id: id ?? this.id,
        senderId: senderId,
        body: body,
        sentAt: sentAt,
        status: status ?? this.status,
        senderName: senderName,
      );

  factory DirectMessage.fromJson(Map<String, dynamic> json) => DirectMessage(
    id: json['id'] as String,
    senderId: json['senderId'] as String,
    body: json['body'] as String,
    sentAt: DateTime.parse(json['sentAt'] as String).toLocal(),
    senderName: json['senderName'] as String?,
  );
}
