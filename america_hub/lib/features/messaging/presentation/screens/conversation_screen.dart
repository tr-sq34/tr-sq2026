import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../application/direct_conversation_controller.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/direct_message.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({
    super.key,
    required this.conversation,
    required this.createController,
  });

  final Conversation conversation;
  final DirectConversationControllerFactory createController;

  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final DirectConversationController _controller;

  /// Message count at the last scroll-to-bottom, so an incoming message scrolls
  /// the thread but a repaint does not.
  int _lastSeenCount = 0;

  @override
  void initState() {
    super.initState();
    _controller = widget.createController(widget.conversation.id);
    _controller.addListener(_onControllerChanged);
    _scroll.addListener(_onScroll);
    _controller.load();
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {});
    final count = _controller.messages.length;
    if (count != _lastSeenCount) {
      _lastSeenCount = count;
      _scrollToBottom();
    }
  }

  void _onScroll() {
    // The list runs oldest-first, so the top edge is where older history goes.
    if (_scroll.position.pixels <= 80) {
      _controller.loadMoreHistory();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    _controller.send(text);
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      body: Column(
        children: [
          // Overlay Header
          _buildHeader(isDarkMode),

          if (widget.conversation.contextLabel != null)
            _ContextPin(label: widget.conversation.contextLabel!),

          // Messages Log Area
          Expanded(child: _buildBody(isDarkMode)),

          // Message Input Field Bar
          _buildInputBar(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildBody(bool isDarkMode) {
    if (_controller.isLoading && _controller.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_controller.errorMessage != null && _controller.isEmpty) {
      return _ThreadError(
        message: _controller.errorMessage!,
        onRetry: _controller.load,
      );
    }

    final messages = _controller.messages;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(16),
      itemCount: messages.length + 1, // +1 for the leading status row
      itemBuilder: (context, index) {
        if (index == 0) {
          return Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: isDarkMode
                    ? const Color(0xFF1E293B)
                    : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _controller.isLoadingMore
                    ? 'Yükleniyor…'
                    : (_controller.hasMoreHistory
                        ? 'Daha eski mesajlar'
                        : 'Sohbetin başlangıcı'),
                style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.bold),
              ),
            ),
          );
        }

        final message = messages[index - 1];
        return _buildMessageBubble(message, isDarkMode);
      },
    );
  }

  Widget _buildHeader(bool isDarkMode) {
    final isGroup = widget.conversation.kind == ConversationKind.group;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 48, 12, 8),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        border: Border(
          bottom: BorderSide(
            color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(isGroup ? Icons.groups_outlined : Icons.person_outline,
                color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.conversation.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          // Calls are 1:1 only; a group has no call target.
          if (!isGroup) ...[
            IconButton(
              icon: const Icon(Icons.call_rounded, size: 20),
              onPressed: () {},
            ),
            IconButton(
              icon: const Icon(Icons.videocam_rounded, size: 20),
              onPressed: () {},
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMessageBubble(DirectMessage message, bool isDarkMode) {
    final mine = message.isMine(_controller.viewerId);
    final failed = message.status == DirectMessageStatus.failed;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: failed ? () => _showRetrySheet(message) : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: mine
                ? null
                : (isDarkMode ? const Color(0xFF1E293B) : Colors.white),
            gradient: mine
                ? LinearGradient(
                    colors: message.status == DirectMessageStatus.sent
                        ? const [Color(0xFF6C5CE7), Color(0xFF4F46E5)]
                        // Not yet acknowledged: dimmed so an undelivered
                        // message never looks delivered.
                        : const [Color(0xFF9B90F0), Color(0xFF8B85E8)],
                  )
                : null,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 0),
              bottomRight: Radius.circular(mine ? 0 : 16),
            ),
            border: mine
                ? null
                : Border.all(
                    color: isDarkMode
                        ? const Color(0xFF334155)
                        : const Color(0xFFE2E8F0),
                  ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Only group threads carry a sender name; in a 1:1 thread the
              // header already says who the other side is.
              if (!mine && message.senderName != null) ...[
                Text(
                  message.senderName!,
                  style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary),
                ),
                const SizedBox(height: 3),
              ],
              Text(
                message.body,
                style: TextStyle(
                    fontSize: 13,
                    color: mine ? Colors.white : (isDarkMode ? Colors.white : Colors.black87)),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      failed ? 'Gönderilemedi · dokun' : _clock(message.sentAt),
                      style: TextStyle(
                          fontSize: 9,
                          color: mine ? Colors.white70 : const Color(0xFF94A3B8)),
                    ),
                    if (mine) ...[
                      const SizedBox(width: 2),
                      Icon(_statusIcon(message.status),
                          size: 12, color: Colors.white70),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static IconData _statusIcon(DirectMessageStatus status) => switch (status) {
        DirectMessageStatus.sending => Icons.schedule_rounded,
        DirectMessageStatus.sent => Icons.done_all_rounded,
        DirectMessageStatus.failed => Icons.error_outline_rounded,
      };

  static String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';

  Future<void> _showRetrySheet(DirectMessage message) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: const Text('Yeniden gönder'),
              onTap: () {
                Navigator.pop(sheetContext);
                _controller.retry(message.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Mesajı sil'),
              onTap: () {
                Navigator.pop(sheetContext);
                _controller.discard(message.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar(bool isDarkMode) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          border: Border(
            top: BorderSide(
              color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
            ),
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.attach_file_rounded, color: Color(0xFF94A3B8)),
              onPressed: () {},
            ),
            Expanded(
              child: TextField(
                controller: _input,
                onSubmitted: (_) => _send(),
                style: TextStyle(color: isDarkMode ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Mesaj yazın...',
                  hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                  filled: true,
                  fillColor: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.send_rounded, color: Colors.white),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF6C5CE7),
                shape:
                    RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadError extends StatelessWidget {
  const _ThreadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded,
                  size: 40, color: Color(0xFF94A3B8)),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
              ),
              const SizedBox(height: 12),
              TextButton(onPressed: onRetry, child: const Text('Tekrar dene')),
            ],
          ),
        ),
      );
}

class _ContextPin extends StatelessWidget {
  const _ContextPin({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0x33E5F3FF),
            border: Border.all(color: const Color(0x667CC6F2)),
            borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          const Icon(Icons.push_pin_outlined, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
              child: Text('İlan detayları · $label',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)))
        ]),
      );
}
