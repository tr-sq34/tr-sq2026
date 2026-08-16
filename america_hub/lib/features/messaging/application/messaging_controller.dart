import 'package:flutter/foundation.dart';
import '../../../core/network/api_exception.dart';
import '../domain/entities/conversation.dart';
import '../domain/repositories/messaging_repository.dart';

class MessagingController extends ChangeNotifier {
  MessagingController({required MessagingRepository repository}) : _repository = repository;
  final MessagingRepository _repository;
  List<Conversation> inbox = const [];
  List<CommunityGroup> groups = const [];
  bool isLoading = false;
  int get unreadCount => inbox.fold(0, (sum, item) => sum + item.unreadCount);
  List<Conversation> get requests => inbox.where((item) => item.kind == ConversationKind.request).toList(growable: false);
  /// Set when the last [load] failed. The previously loaded inbox is kept, so
  /// a dropped connection never wipes the list the user is looking at.
  String? errorMessage;
  Future<void> load() async { isLoading = true; errorMessage = null; notifyListeners(); try { inbox = await _repository.getInbox(); groups = await _repository.getGroups(); } on ApiException catch (error) { errorMessage = error.message; } catch (_) { errorMessage = 'Mesajlar yüklenemedi. Lütfen tekrar deneyin.'; } finally { isLoading = false; notifyListeners(); } }
  Future<void> markRead(String id) async { await _repository.markConversationRead(id); inbox = [for (final item in inbox) if (item.id == id) item.copyWith(unreadCount: 0) else item]; notifyListeners(); }
  /// Applies the membership the server decided on, not the one the tapped
  /// button implied: a public group joins outright, a private one only queues a
  /// request, and the client must not guess which.
  Future<GroupMembershipStatus?> join(String id) async {
    final GroupMembershipStatus status;
    try {
      status = await _repository.joinGroup(id);
    } on ApiException catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return null;
    } catch (_) {
      errorMessage = 'Gruba katılınamadı. Lütfen tekrar deneyin.';
      notifyListeners();
      return null;
    }
    groups = [
      for (final item in groups)
        if (item.id == id)
          item.copyWith(
            membershipStatus: status,
            // The count only moves when the join actually took effect; a
            // pending request is not a member yet.
            members: status == GroupMembershipStatus.joined && !item.isJoined ? item.members + 1 : item.members,
          )
        else
          item,
    ];
    notifyListeners();
    return status;
  }

  Future<bool> leave(String id) async {
    try {
      await _repository.leaveGroup(id);
    } on ApiException catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Gruptan ayrılınamadı. Lütfen tekrar deneyin.';
      notifyListeners();
      return false;
    }
    groups = [
      for (final item in groups)
        if (item.id == id)
          item.copyWith(
            membershipStatus: GroupMembershipStatus.none,
            members: item.isJoined && item.members > 0 ? item.members - 1 : item.members,
          )
        else
          item,
    ];
    notifyListeners();
    return true;
  }

  Future<List<GroupJoinRequest>> joinRequests(String groupId) => _repository.getJoinRequests(groupId);

  /// Accepting adds a member, declining removes the request without a trace so
  /// the same person may ask again later.
  Future<bool> decideJoinRequest(String groupId, String userId, {required bool accept}) async {
    try {
      await _repository.respondToJoinRequest(groupId, userId, accept: accept);
    } catch (_) {
      return false;
    }
    if (accept) {
      groups = [for (final item in groups) if (item.id == groupId) item.copyWith(members: item.members + 1) else item];
      notifyListeners();
    }
    return true;
  }

  Future<bool> createGroup({
    required String name,
    required String city,
    required GroupPrivacy privacy,
    String? imageUrl,
    String? description,
  }) async {
    errorMessage = null;
    if (name.trim().length < 3 || city.trim().isEmpty) return false;
    final CommunityGroup group;
    try {
      group = await _repository.createGroup(
        name: name.trim(),
        city: city.trim(),
        privacy: privacy,
        imageUrl: imageUrl,
        description: description?.trim().isEmpty ?? true
            ? null
            : description!.trim(),
      );
    } on ApiException catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Grup oluşturulamadı. Lütfen tekrar deneyin.';
      notifyListeners();
      return false;
    }
    groups = [group, ...groups];
    notifyListeners();
    return true;
  }

  /// Kurucunun grup künyesini düzenlemesi. Değişen kaydı listeye yazıyor ki
  /// ayarlar kapandığında kart yeni adı göstersin.
  Future<bool> updateGroup(
    String groupId, {
    String? name,
    String? city,
    Object? description = CommunityGroup.unchanged,
    Object? imageUrl = CommunityGroup.unchanged,
  }) async {
    errorMessage = null;
    final CommunityGroup group;
    try {
      group = await _repository.updateGroup(
        groupId,
        name: name,
        city: city,
        description: description,
        imageUrl: imageUrl,
      );
    } on ApiException catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Grup bilgileri kaydedilemedi. Lütfen tekrar deneyin.';
      notifyListeners();
      return false;
    }
    groups = [
      for (final item in groups)
        if (item.id == groupId) group else item,
    ];
    notifyListeners();
    return true;
  }

  Future<List<GroupMember>> groupMembers(String groupId) =>
      _repository.getGroupMembers(groupId);

  /// Davet gönderildi mi, gönderildiyse hangi durumda kaldı. `null` dönmesi
  /// gönderilemediği anlamına geliyor; sebebi [errorMessage] içinde.
  Future<GroupMembershipStatus?> inviteMember(
    String groupId,
    String userId,
  ) async {
    errorMessage = null;
    try {
      return await _repository.inviteGroupMember(groupId, userId);
    } on ApiException catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return null;
    } catch (_) {
      errorMessage = 'Davet gönderilemedi. Lütfen tekrar deneyin.';
      notifyListeners();
      return null;
    }
  }

  /// [wasJoined] false ise geri alınan şey bir davet: o kişi hiç üye
  /// olmadığından sayaç da yerinde kalıyor.
  Future<bool> removeMember(
    String groupId,
    String userId, {
    required bool wasJoined,
  }) async {
    errorMessage = null;
    try {
      await _repository.removeGroupMember(groupId, userId);
    } on ApiException catch (error) {
      errorMessage = error.message;
      notifyListeners();
      return false;
    } catch (_) {
      errorMessage = 'Üye çıkarılamadı. Lütfen tekrar deneyin.';
      notifyListeners();
      return false;
    }
    if (wasJoined) {
      groups = [
        for (final item in groups)
          if (item.id == groupId && item.members > 1)
            item.copyWith(members: item.members - 1)
          else
            item,
      ];
    }
    notifyListeners();
    return true;
  }
  Future<Conversation?> respondToRequest(String id, RequestDecision decision) async {
    final index = inbox.indexWhere((item) => item.id == id);
    if (index < 0) return null;
    final item = inbox[index];
    try {
      await _repository.respondToRequest(id, decision);
    } catch (_) {
      return null;
    }

    final updated = <Conversation>[];
    for (final value in inbox) {
      if (value.id != id) {
        updated.add(value);
      } else if (decision == RequestDecision.accepted) {
        updated.add(value.copyWith(
          requestDecision: decision,
          unreadCount: 0,
          kind: ConversationKind.direct,
        ));
      }
    }
    inbox = updated;
    notifyListeners();
    return decision == RequestDecision.accepted
        ? item.copyWith(requestDecision: decision, unreadCount: 0, kind: ConversationKind.direct)
        : null;
  }
}
