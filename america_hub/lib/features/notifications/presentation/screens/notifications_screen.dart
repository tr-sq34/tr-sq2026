import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../application/notifications_controller.dart';
import '../../domain/entities/app_notification.dart';

/// The bell's destination.
///
/// The list is now fed by `member_notifications`: a comment on your post, a
/// like on it, someone saving or liking your listing. Everything else — friend
/// requests, badges, event reminders — still has no publisher, so it still does
/// not appear. An empty list remains the honest answer for a member nobody has
/// reacted to yet, rather than a demo item dressed up as news.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, required this.controller});

  final NotificationsController controller;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.white,
      elevation: 0,
      title: const Text(
        'Bildirimler',
        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
      ),
      actions: [
        AnimatedBuilder(
          animation: widget.controller,
          builder: (context, _) => widget.controller.unreadCount == 0
              ? const SizedBox.shrink()
              : TextButton(
                  onPressed: widget.controller.markAllRead,
                  child: const Text(
                    'Tümünü okundu işaretle',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
        ),
      ],
    ),
    body: AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (controller.isLoading && controller.items.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.items.isEmpty) return const _EmptyState();
        return RefreshIndicator(
          onRefresh: controller.load,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: controller.items.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) => _NotificationTile(
              notification: controller.items[index],
              onTap: () => controller.open(controller.items[index]),
            ),
          ),
        );
      },
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: .08),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_none_rounded,
              size: 34,
              color: AppColors.primary.withValues(alpha: .7),
            ),
          ),
          const SizedBox(height: 18),
          const Text(
            'Henüz bildirim yok',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Paylaşımlarına gelen yorumlar ve beğeniler, ilanlarına gelen ilgi '
            'burada görünecek.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF64748B), height: 1.4),
          ),
        ],
      ),
    ),
  );
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});

  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    tileColor: notification.isRead
        ? null
        : AppColors.primary.withValues(alpha: .05),
    leading: CircleAvatar(
      backgroundColor: AppColors.primary.withValues(alpha: .12),
      child: Icon(_iconFor(notification.type), size: 20, color: AppColors.primary),
    ),
    title: Text(
      notification.title,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    ),
    subtitle: Text(
      notification.body,
      style: const TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
    ),
  );

  static IconData _iconFor(AppNotificationType type) => switch (type) {
    AppNotificationType.specialRequest => Icons.volunteer_activism_rounded,
    AppNotificationType.friendRequest => Icons.person_add_alt_1_outlined,
    AppNotificationType.postComment => Icons.mode_comment_outlined,
    AppNotificationType.postLike => Icons.favorite_border_rounded,
    AppNotificationType.listingSaved => Icons.bookmark_border_rounded,
    AppNotificationType.listingLiked => Icons.storefront_outlined,
    AppNotificationType.eventReminder => Icons.event_outlined,
    AppNotificationType.system => Icons.info_outline_rounded,
  };
}
