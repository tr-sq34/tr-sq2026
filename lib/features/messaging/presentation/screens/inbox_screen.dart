import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../application/messaging_controller.dart';
import '../../domain/entities/conversation.dart';
import 'conversation_screen.dart';
import '../widgets/create_group_sheet.dart';

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, required this.controller});
  final MessagingController controller;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 4, vsync: this);

  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) => Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            backgroundColor: AppColors.background,
            surfaceTintColor: Colors.transparent,
            title: const Text('Mesajlar', style: TextStyle(fontWeight: FontWeight.w800)),
            actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.add_comment_outlined))],
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textMuted,
              tabs: [
                const Tab(text: 'Gelen Kutusu'),
                Tab(text: 'Okunmamış${widget.controller.unreadCount > 0 ? ' (${widget.controller.unreadCount})' : ''}'),
                const Tab(text: 'Topluluklar'),
                Tab(text: 'İstekler${widget.controller.requests.isNotEmpty ? ' (${widget.controller.requests.length})' : ''}'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              _conversations(widget.controller.inbox),
              _conversations(widget.controller.inbox.where((item) => item.unreadCount > 0).toList(), emptyMessage: 'Okunmamış mesajınız bulunmuyor'),
              _groups(),
              _requests(),
            ],
          ),
        ),
      );

  Widget _conversations(List<Conversation> items, {String? emptyMessage}) {
    if (items.isEmpty) return _EmptyState(message: emptyMessage);
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 9),
      itemBuilder: (_, index) {
        final item = items[index];
        return ListTile(
          tileColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          leading: CircleAvatar(
            backgroundColor: AppColors.primary.withValues(alpha: .14),
            child: Icon(item.kind == ConversationKind.request ? Icons.volunteer_activism_outlined : Icons.person_outline, color: AppColors.primary),
          ),
          title: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (item.contextLabel != null) Text(item.contextLabel!, style: const TextStyle(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w700)),
          ]),
          trailing: item.unreadCount > 0 ? CircleAvatar(radius: 11, backgroundColor: AppColors.accentRose, child: Text('${item.unreadCount}', style: const TextStyle(color: Colors.white, fontSize: 11))) : null,
          onTap: () async {
            await widget.controller.markRead(item.id);
            if (!mounted) return;
            Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ConversationScreen(conversation: item)));
          },
        );
      },
    );
  }

  Widget _groups() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(onPressed: () => showModalBottomSheet<void>(context: context, isScrollControlled: true, useSafeArea: true, backgroundColor: Colors.transparent, builder: (_) => CreateGroupSheet(controller: widget.controller)), icon: const Icon(Icons.add), label: const Text('Grup oluştur')),
          const SizedBox(height: 16),
          for (final group in widget.controller.groups)
            Card(
              child: ListTile(
                leading: const CircleAvatar(backgroundColor: Color(0xFFF0E9FF), child: Icon(Icons.groups_outlined, color: AppColors.primary)),
                title: Text(group.name, style: const TextStyle(fontWeight: FontWeight.w800)),
                subtitle: Text('${group.city} · ${group.members} üye'),
                trailing: group.isJoined ? PopupMenuButton<String>(icon: const Icon(Icons.more_horiz_rounded), itemBuilder: (_) => const [PopupMenuItem(value: 'invite', child: Text('Davet bağlantısını kopyala')), PopupMenuItem(value: 'qr', child: Text('QR kod göster')), PopupMenuItem(value: 'share', child: Text('Akışta paylaş'))], onSelected: (_) => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Paylaşım aksiyonu mock olarak hazır.')))) : TextButton(onPressed: () => widget.controller.join(group.id), child: const Text('Katıl')),
              ),
            ),
        ],
      );

  Widget _requests() {
    final items = widget.controller.requests;
    if (items.isEmpty) return const _EmptyState(message: 'Yeni bir mesaj isteğiniz yok');
    return ListView.separated(
      padding: const EdgeInsets.all(16), itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        final isTravel = item.title.contains('Bavul');
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [BoxShadow(color: Color(0x100E0B18), blurRadius: 14, offset: Offset(0, 5))]),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Container(width: 38, height: 38, decoration: BoxDecoration(color: isTravel ? const Color(0xFFE5F3FF) : const Color(0xFFFFF1D8), borderRadius: BorderRadius.circular(12)), child: Icon(isTravel ? Icons.luggage_outlined : Icons.volunteer_activism_outlined, color: AppColors.primary)), const SizedBox(width: 10), Expanded(child: Text(item.title, style: const TextStyle(fontWeight: FontWeight.w800))), const Icon(Icons.more_horiz_rounded, color: AppColors.textMuted)]),
            const SizedBox(height: 12), Text(item.preview, style: const TextStyle(height: 1.4)),
            if (item.contextLabel != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(item.contextLabel!, style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w700))),
            const SizedBox(height: 14), Row(children: [Expanded(child: OutlinedButton(onPressed: () => widget.controller.respondToRequest(item.id, RequestDecision.declined), child: const Text('Reddet'))), const SizedBox(width: 10), Expanded(child: FilledButton(onPressed: () async { final conversation = await widget.controller.respondToRequest(item.id, RequestDecision.accepted); if (!mounted || conversation == null) return; Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ConversationScreen(conversation: conversation))); }, child: const Text('Kabul et')))]),
          ]),
        );
      },
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({this.message});
  final String? message;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 48),
          const Icon(Icons.forum_outlined, size: 58, color: AppColors.primary),
          const SizedBox(height: 14),
          Text(message ?? 'Gurbet köprünü kur', textAlign: TextAlign.center, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(message == null ? 'Bölgenizdeki topluluklara katılın veya bir hemşehrine selam verin.' : '', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textMuted)),
          if (message == null) ...[const SizedBox(height: 24), const Text('Buzları kır', style: TextStyle(fontWeight: FontWeight.w800)), Wrap(spacing: 8, runSpacing: 8, children: [ActionChip(label: const Text('Selam, tanışalım mı? ☕'), onPressed: () {}), ActionChip(label: const Text('New York’ta yeniyim 👋'), onPressed: () {})])],
        ],
      );
}
