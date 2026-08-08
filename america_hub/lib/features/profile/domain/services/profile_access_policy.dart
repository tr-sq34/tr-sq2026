import '../entities/friendship.dart';
import '../entities/user_profile.dart';
abstract final class ProfileAccessPolicy { static bool canViewFullProfile({required UserProfile profile, required FriendshipStatus relationship, required bool isOwner})=>isOwner||profile.visibility==ProfileVisibility.public||relationship==FriendshipStatus.friends; static bool canMessage(FriendshipStatus relationship)=>relationship==FriendshipStatus.friends; static bool isBlocked(FriendshipStatus relationship)=>relationship==FriendshipStatus.blocked; }
