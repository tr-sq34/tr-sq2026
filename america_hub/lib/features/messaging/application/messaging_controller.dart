import 'package:flutter/foundation.dart';
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
  Future<void> load() async { isLoading = true; notifyListeners(); try { inbox = await _repository.getInbox(); groups = await _repository.getGroups(); } finally { isLoading = false; notifyListeners(); } }
  Future<void> markRead(String id) async { await _repository.markConversationRead(id); inbox = [for (final item in inbox) if (item.id == id) item.copyWith(unreadCount: 0) else item]; notifyListeners(); }
  Future<void> join(String id) async { await _repository.joinGroup(id); groups = [for (final item in groups) if (item.id == id) item.copyWith(membershipStatus: item.privacy == GroupPrivacy.public ? GroupMembershipStatus.joined : GroupMembershipStatus.requested) else item]; notifyListeners(); }
  Future<bool> createGroup({required String name, required String city, required GroupPrivacy privacy, String? imageUrl}) async { if(name.trim().length<3||city.trim().isEmpty)return false; final group=await _repository.createGroup(name:name.trim(),city:city.trim(),privacy:privacy,imageUrl:imageUrl); groups=[group,...groups]; notifyListeners(); return true; }
  Future<Conversation?> respondToRequest(String id, RequestDecision decision) async {
    final index = inbox.indexWhere((item) => item.id == id);
    if (index < 0) return null;
    final item = inbox[index];
    await _repository.respondToRequest(id, decision);

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
