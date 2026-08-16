import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/design/app_radius.dart';
import '../../application/support_controller.dart';
import '../../domain/support_request.dart';
import 'support_screen.dart' show supportTimeAgo;

/// Tek bir destek talebinin yazışması.
///
/// Cevabı yazan kişinin adı burada yok, olamaz da: sunucu göndermiyor. Muhatap
/// bir çalışan değil, platform — ve bir moderatörün adını üyeye açmak, o
/// moderatörü hedef yapar.
class SupportThreadScreen extends StatefulWidget {
  const SupportThreadScreen({
    super.key,
    required this.controller,
    required this.requestId,
    this.subject,
  });

  final SupportController controller;
  final String requestId;

  /// Listeden gelindiğinde başlık elimizde; bildirimden gelindiğinde yalnızca
  /// talep kimliği var ve başlık yazışmayla birlikte geliyor.
  final String? subject;

  @override
  State<SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends State<SupportThreadScreen> {
  final _reply = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.controller.openRequest(widget.requestId);
    });
  }

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final sent = await widget.controller.reply(widget.requestId, _reply.text);
    if (!mounted || !sent) return;
    _reply.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        // Başlık da denetleyiciyi dinliyor: bildirimden gelindiğinde elimizde
        // yalnızca kimlik var, konu yazışmayla birlikte geliyor.
        title: AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => Text(
            widget.controller.openThread?.subject ??
                widget.subject ??
                'Destek talebi',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        backgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
      ),
      body: AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final controller = widget.controller;
          final thread = controller.openThread;

          if (controller.isThreadLoading && thread == null) {
            return const Center(child: CircularProgressIndicator());
          }
          // Yazışma açılamadıysa boş bir sayfa değil, sebebi görünüyor.
          if (thread == null) {
            return Padding(
              padding: const EdgeInsets.all(20),
              child: _Notice(
                message: controller.threadError == null
                    ? 'Yazışma açılamadı.'
                    : '${controller.threadError}\n\nBu, yazışmanın silindiği anlamına gelmez — okunamadı.',
                onRetry: () => controller.openRequest(widget.requestId),
              ),
            );
          }

          final closed = thread.status == SupportStatus.closed;
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                  children: [
                    _Header(thread: thread),
                    const SizedBox(height: 12),
                    if (thread.messages.isEmpty)
                      const Text(
                        'Bu talepte gösterilecek mesaj yok.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                      ),
                    for (final message in thread.messages) ...[
                      _MessageBubble(message: message),
                      const SizedBox(height: 10),
                    ],
                    if (controller.threadError case final String message) ...[
                      const SizedBox(height: 4),
                      _Notice(message: message),
                    ],
                  ],
                ),
              ),
              if (closed)
                const _ClosedFooter()
              else
                _Composer(
                  controller: _reply,
                  busy: controller.isSending,
                  onSend: _send,
                  onChanged: () => setState(() {}),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.thread});

  final SupportRequest thread;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.all(AppRadius.card),
        border: Border.all(color: AppColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${thread.topic.label} · ${thread.status.label}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Açıldı: ${supportTimeAgo(thread.createdAt)}'
            '${thread.lastStaffAt == null ? ' · henüz yanıtlanmadı' : ' · son yanıt ${supportTimeAgo(thread.lastStaffAt!)}'}',
            style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
          ),
          // Kapanışın sebebini söylemeyen bir kapanış, üyeye hiçbir şey
          // söylememektir.
          if (thread.closureReason case final String reason) ...[
            const SizedBox(height: 8),
            Text(
              'Kapanış gerekçesi: $reason',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final SupportMessage message;

  @override
  Widget build(BuildContext context) {
    final staff = message.fromStaff;
    return Align(
      alignment: staff ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * .82,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: staff ? AppColors.surface : AppColors.profileTint,
          borderRadius: const BorderRadius.all(AppRadius.card),
          border: Border.all(
            color: staff ? AppColors.surfaceBorder : AppColors.profileBorder,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              staff ? 'Destek ekibi' : 'Sen',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: staff ? AppColors.primary : AppColors.profileAccent,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message.body,
              style: const TextStyle(
                fontSize: 13.5,
                height: 1.4,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              supportTimeAgo(message.createdAt),
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.busy,
    required this.onSend,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool busy;
  final Future<void> Function() onSend;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final valid = controller.text.trim().length >= 2;
    return Container(
      padding: EdgeInsets.fromLTRB(
        12,
        10,
        12,
        10 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              maxLength: 4000,
              onChanged: (_) => onChanged(),
              decoration: const InputDecoration(
                hintText: 'Ek bir şey yaz…',
                counterText: '',
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: busy || !valid ? null : () => onSend(),
            style: IconButton.styleFrom(backgroundColor: AppColors.primary),
            icon: busy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.send_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _ClosedFooter extends StatelessWidget {
  const _ClosedFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
      decoration: const BoxDecoration(
        color: AppColors.canvas,
        border: Border(top: BorderSide(color: AppColors.surfaceBorder)),
      ),
      child: const Text(
        'Bu talep kapandı. Konu sürüyorsa yeni bir talep aç — kapanmış bir yazışmanın altına '
        'yazılan mesaj kimsenin kuyruğuna düşmez.',
        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    const color = Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: const BorderRadius.all(AppRadius.card),
        border: Border.all(color: color.withValues(alpha: .32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: const TextStyle(fontSize: 12.5, height: 1.4, color: color),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: 8),
            OutlinedButton(onPressed: onRetry, child: const Text('Tekrar dene')),
          ],
        ],
      ),
    );
  }
}
