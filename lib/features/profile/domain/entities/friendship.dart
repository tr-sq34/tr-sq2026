enum FriendshipStatus { none, pendingIncoming, pendingOutgoing, friends, blocked }
class Friendship { const Friendship({required this.userId, required this.status}); final String userId; final FriendshipStatus status; }
