import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/widgets/app_text_field.dart';
import '../../domain/entities/conversation.dart';

class ConversationScreen extends StatefulWidget {
  const ConversationScreen({super.key, required this.conversation});
  final Conversation conversation;
  @override State<ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<ConversationScreen> {
  final _input = TextEditingController();
  final List<_ChatMessage> _messages = [];
  @override void initState() { super.initState(); if (widget.conversation.id == 'dm-1') _messages.addAll(const [_ChatMessage('Merhaba Ahmet! Bu hafta sonu kahve içmek ister misin?', false), _ChatMessage('Olur, cumartesi benim için uygun. ☕', true)]); }
  @override void dispose() { _input.dispose(); super.dispose(); }
  void _send() { final text = _input.text.trim(); if (text.isEmpty) return; setState(() { _messages.add(_ChatMessage(text, true)); _input.clear(); }); }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(backgroundColor: AppColors.background, surfaceTintColor: Colors.transparent, title: Text(widget.conversation.title, style: const TextStyle(fontWeight: FontWeight.w800))),
    body: Column(children: [
      if (widget.conversation.contextLabel != null) _ContextPin(label: widget.conversation.contextLabel!),
      Expanded(child: _messages.isEmpty ? const Center(child: Text('Mesaj kutunuz boş', style: TextStyle(color: AppColors.textMuted))) : ListView.separated(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), itemCount: _messages.length, separatorBuilder: (_, __) => const SizedBox(height: 8), itemBuilder: (_, index) { final message = _messages[index]; return Align(alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft, child: Container(constraints: const BoxConstraints(maxWidth: 300), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10), decoration: BoxDecoration(color: message.mine ? AppColors.primary : Colors.white, borderRadius: BorderRadius.circular(18)), child: Text(message.text, style: TextStyle(color: message.mine ? Colors.white : AppColors.textPrimary, height: 1.35)))); })),
      SafeArea(top: false, child: Container(color: Colors.white, padding: const EdgeInsets.fromLTRB(12, 8, 12, 12), child: Column(mainAxisSize: MainAxisSize.min, children: [_ActionBar(), Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: AppTextField(controller: _input, label: '', hint: 'Mesaj yaz...', prefixIcon: Icons.chat_bubble_outline, showLabel: false, minLines: 1, maxLines: 5, maxLength: 1000, onSubmitted: (_) => _send())), const SizedBox(width: 8), FilledButton(onPressed: _send, style: FilledButton.styleFrom(shape: const CircleBorder(), padding: const EdgeInsets.all(13)), child: const Icon(Icons.send_rounded))])]))),
    ]),
  );
}
class _ActionBar extends StatelessWidget { @override Widget build(BuildContext context) => Row(children: [for (final icon in const [Icons.mic_none_rounded, Icons.image_outlined, Icons.camera_alt_outlined, Icons.emoji_emotions_outlined]) Padding(padding: const EdgeInsets.only(right: 6), child: IconButton.filledTonal(onPressed: () {}, icon: Icon(icon, size: 19), style: IconButton.styleFrom(backgroundColor: const Color(0xFFF4F2F8), foregroundColor: AppColors.primary))) ]); }
class _ChatMessage { const _ChatMessage(this.text, this.mine); final String text; final bool mine; }
class _ContextPin extends StatelessWidget { const _ContextPin({required this.label}); final String label; @override Widget build(BuildContext context) => Container(margin: const EdgeInsets.fromLTRB(16, 8, 16, 4), padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0x33E5F3FF), border: Border.all(color: const Color(0x667CC6F2)), borderRadius: BorderRadius.circular(14)), child: Row(children: [const Icon(Icons.push_pin_outlined, color: AppColors.primary), const SizedBox(width: 8), Expanded(child: Text('İlan detayları · $label', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12)))])); }
