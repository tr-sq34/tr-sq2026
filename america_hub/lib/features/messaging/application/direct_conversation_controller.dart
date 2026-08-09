import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/uuid.dart';
import '../domain/entities/direct_message.dart';
import '../domain/repositories/direct_message_repository.dart';

/// Builds the controller for a thread the user just opened.
///
/// The chat screen is pushed from several places, none of which should have to
/// know which repository or which signed-in user is behind it, so the wiring is
/// handed down as this factory instead.
typedef DirectConversationControllerFactory =
    DirectConversationController Function(String conversationId);

/// Drives one open chat thread.
///
/// Messages are kept oldest-first, which is the order the screen renders them
/// in. The gateway hands them back newest-first because that is the direction
/// history pagination runs, so every page is reversed on the way in.
class DirectConversationController extends ChangeNotifier {
  DirectConversationController({
    required DirectMessageRepository repository,
    required this.conversationId,
    required this.viewerId,
  }) : _repository = repository;

  static const _pageSize = 30;

  /// There is no push channel: the gateway exposes no websocket and the
  /// homeserver is not reachable from the app. Polling the newest page is the
  /// only way an incoming message can appear while the screen is open.
  static const _pollInterval = Duration(seconds: 5);

  final DirectMessageRepository _repository;
  final String conversationId;

  /// Used to decide which bubbles are the viewer's own.
  final String viewerId;

  /// Acknowledged by the gateway, oldest-first.
  List<DirectMessage> _confirmed = const [];

  /// Composed on this device and not yet acknowledged. They always sort after
  /// everything confirmed, so appending them is enough to keep the thread in
  /// chronological order.
  List<DirectMessage> _pending = const [];

  final Set<String> _knownIds = {};

  Timer? _poll;
  bool _disposed = false;
  String? _historyCursor;

  bool isLoading = false;
  bool isLoadingMore = false;

  /// Set when the initial load fails. Send failures are reported per message
  /// via [DirectMessageStatus.failed] instead, so one bad send never blanks
  /// the thread.
  String? errorMessage;

  List<DirectMessage> get messages => [..._confirmed, ..._pending];
  bool get hasMoreHistory => _historyCursor != null && _historyCursor!.isNotEmpty;
  bool get isEmpty => _confirmed.isEmpty && _pending.isEmpty;

  Future<void> load() async {
    isLoading = true;
    errorMessage = null;
    _notify();
    try {
      final page = await _repository.fetchMessages(
        conversationId,
        limit: _pageSize,
      );
      _confirmed = page.items.reversed.toList(growable: false);
      _knownIds
        ..clear()
        ..addAll(_confirmed.map((message) => message.id));
      _historyCursor = page.nextCursor;
      _startPolling();
    } on ApiException catch (error) {
      errorMessage = error.message;
    } catch (_) {
      errorMessage = 'Mesajlar yüklenemedi. Lütfen tekrar deneyin.';
    } finally {
      isLoading = false;
      _notify();
    }
  }

  /// Pulls one older page. Older messages are prepended, so the scroll position
  /// the user is looking at keeps showing the same content.
  Future<void> loadMoreHistory() async {
    if (isLoadingMore || !hasMoreHistory) return;
    isLoadingMore = true;
    _notify();
    try {
      final page = await _repository.fetchMessages(
        conversationId,
        cursor: _historyCursor,
        limit: _pageSize,
      );
      final older = page.items.reversed
          .where((message) => _knownIds.add(message.id))
          .toList(growable: false);
      _confirmed = [...older, ..._confirmed];
      _historyCursor = page.nextCursor;
    } on ApiException {
      // Leave the thread as it is; the user can pull again.
    } catch (_) {
      // Same reasoning as above.
    } finally {
      isLoadingMore = false;
      _notify();
    }
  }

  Future<void> send(String rawBody) async {
    final body = rawBody.trim();
    if (body.isEmpty) return;
    final draft = DirectMessage(
      // Replaced by the gateway's event ID once delivered. Until then it is
      // also the idempotency key, so a retry cannot duplicate the message.
      id: generateUuidV4(),
      senderId: viewerId,
      body: body,
      sentAt: DateTime.now(),
      status: DirectMessageStatus.sending,
    );
    _pending = [..._pending, draft];
    _notify();
    await _deliver(draft);
  }

  /// Resends a message that previously failed, reusing its idempotency key.
  Future<void> retry(String messageId) async {
    final index = _pending.indexWhere((message) => message.id == messageId);
    if (index < 0) return;
    final retried = _pending[index].copyWith(
      status: DirectMessageStatus.sending,
    );
    _pending = [..._pending]..[index] = retried;
    _notify();
    await _deliver(retried);
  }

  /// Drops a failed message the user gave up on.
  void discard(String messageId) {
    _pending = _pending
        .where((message) => message.id != messageId)
        .toList(growable: false);
    _notify();
  }

  Future<void> _deliver(DirectMessage draft) async {
    try {
      final eventId = await _repository.sendMessage(
        conversationId: conversationId,
        body: draft.body,
        idempotencyKey: draft.id,
      );
      _pending = _pending
          .where((message) => message.id != draft.id)
          .toList(growable: false);
      // Polling may already have picked the message up under its event ID.
      if (_knownIds.add(eventId)) {
        _confirmed = [
          ..._confirmed,
          draft.copyWith(id: eventId, status: DirectMessageStatus.sent),
        ];
      }
    } catch (_) {
      _pending = [
        for (final message in _pending)
          if (message.id == draft.id)
            message.copyWith(status: DirectMessageStatus.failed)
          else
            message,
      ];
    } finally {
      _notify();
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollInterval, (_) => _pollNewest());
  }

  Future<void> _pollNewest() async {
    if (_disposed) return;
    try {
      final page = await _repository.fetchMessages(
        conversationId,
        limit: _pageSize,
      );
      if (_disposed) return;
      final fresh = page.items.reversed
          .where((message) => _knownIds.add(message.id))
          .toList(growable: false);
      if (fresh.isEmpty) return;
      _confirmed = [..._confirmed, ...fresh];
      _notify();
    } catch (_) {
      // A failed poll is not worth surfacing: the next tick retries, and the
      // thread on screen is still valid.
    }
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}
