import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../application/community_special_request_controller.dart';
import '../../domain/entities/community_post.dart';
import '../../domain/entities/community_special_request.dart';

class SpecialPostRequestSheet extends StatefulWidget {
  const SpecialPostRequestSheet({super.key, required this.post, required this.controller});
  final CommunityPost post;
  final CommunitySpecialRequestController controller;

  @override
  State<SpecialPostRequestSheet> createState() => _SpecialPostRequestSheetState();
}

class _SpecialPostRequestSheetState extends State<SpecialPostRequestSheet> {
  final _message = TextEditingController();

  @override
  void dispose() { _message.dispose(); super.dispose(); }

  CommunitySpecialRequestType get _type => widget.post.purpose == CommunityPostPurpose.travelerMatch
      ? CommunitySpecialRequestType.travelerMatch
      : CommunitySpecialRequestType.imeceOffer;

  Future<void> _send() async {
    final isSent = await widget.controller.send(postId: widget.post.id, type: _type, message: _message.text);
    if (!mounted) return;
    if (isSent) { Navigator.of(context).pop(); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('İsteğin gönderildi.'))); }
  }

  @override
  Widget build(BuildContext context) {
    final isTravel = _type == CommunitySpecialRequestType.travelerMatch;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(color: Colors.white, borderRadius: const BorderRadius.vertical(top: Radius.circular(28)), child: SafeArea(top: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: AnimatedBuilder(animation: widget.controller, builder: (context, _) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 38, height: 4, decoration: BoxDecoration(color: const Color(0xFFD8D5DF), borderRadius: BorderRadius.circular(99)))),
          const SizedBox(height: 18),
          Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: isTravel ? const Color(0xFFE5F3FF) : const Color(0xFFFFF1D8), borderRadius: BorderRadius.circular(14)), child: Icon(isTravel ? Icons.luggage_outlined : Icons.volunteer_activism_outlined, color: AppColors.primary)), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(isTravel ? 'Eşleşme isteği gönder' : 'Destek teklif et', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)), Text(widget.post.authorName, style: const TextStyle(color: AppColors.textMuted))]))]),
          const SizedBox(height: 18),
          if (isTravel && widget.post.travelerMatch != null) Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: const Color(0xFFF6FBFF), borderRadius: BorderRadius.circular(14)), child: Text('${widget.post.travelerMatch!.from} → ${widget.post.travelerMatch!.to}\n${widget.post.travelerMatch!.packageDetails}', style: const TextStyle(height: 1.45))),
          if (isTravel) const SizedBox(height: 14),
          TextField(controller: _message, maxLength: 500, minLines: 3, maxLines: 5, decoration: InputDecoration(hintText: isTravel ? 'Neyi göndermek veya almak istediğini yaz...' : 'Nasıl destek olabileceğini yaz...', filled: true, fillColor: const Color(0xFFF8F7FA), border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none))),
          if (widget.controller.errorMessage != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(widget.controller.errorMessage!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: widget.controller.isSubmitting ? null : _send, icon: const Icon(Icons.send_rounded), label: Text(isTravel ? 'Eşleşme isteği gönder' : 'Teklif gönder'))),
        ])),
      ))),
    );
  }
}
