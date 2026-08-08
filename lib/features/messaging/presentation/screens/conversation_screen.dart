import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../domain/entities/conversation.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversation});
  final Conversation conversation;
  @override
  State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _input = TextEditingController();
  final List<_ChatMessage> _messages = [];

  @override
  void initState() {
    super.initState();
    if (widget.conversation.id == 'dm-1') {
      _messages.addAll(const [
        _ChatMessage('Merhaba Ahmet! Bu hafta sonu kahve içmek ister misin?', false),
        _ChatMessage('Olur, cumartesi benim için uygun. ☕', true)
      ]);
    }
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _send() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_ChatMessage(text, true));
      _input.clear();
    });
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
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length + 1, // +1 for the "Today" divider
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
                      child: const Text('Bugün',
                          style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  );
                }

                final message = _messages[index - 1];
                return _buildMessageBubble(message, isDarkMode);
              },
            ),
          ),

          // Message Input Field Bar
          _buildInputBar(isDarkMode),
        ],
      ),
    );
  }

  Widget _buildHeader(bool isDarkMode) {
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
            child: const Icon(Icons.person_outline, color: AppColors.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.conversation.title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const Row(
                  children: [
                    Icon(Icons.circle, size: 8, color: Color(0xFF10B981)),
                    SizedBox(width: 4),
                    Text('Çevrimiçi',
                        style: TextStyle(fontSize: 11, color: Color(0xFF10B981))),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.call_rounded, size: 20),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.videocam_rounded, size: 20),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage message, bool isDarkMode) {
    return Align(
      alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: message.mine
              ? null
              : (isDarkMode ? const Color(0xFF1E293B) : Colors.white),
          gradient: message.mine
              ? const LinearGradient(
                  colors: [Color(0xFF6C5CE7), Color(0xFF4F46E5)],
                )
              : null,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(message.mine ? 16 : 0),
            bottomRight: Radius.circular(message.mine ? 0 : 16),
          ),
          border: message.mine
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
            Text(
              message.text,
              style: TextStyle(
                  fontSize: 13,
                  color: message.mine ? Colors.white : (isDarkMode ? Colors.white : Colors.black87)),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '10:44',
                    style: TextStyle(
                        fontSize: 9,
                        color: message.mine ? Colors.white70 : const Color(0xFF94A3B8)),
                  ),
                  if (message.mine) ...[
                    const SizedBox(width: 2),
                    const Icon(Icons.done_all_rounded,
                        size: 12, color: Colors.white70),
                  ],
                ],
              ),
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

class _ChatMessage {
  const _ChatMessage(this.text, this.mine);
  final String text;
  final bool mine;
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
