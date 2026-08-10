import 'package:flutter/material.dart';

/// The bar that stays put across every tab of the shell.
///
/// It used to live inside `DiscoverScreen`, which is why the menu button
/// vanished the moment anyone left the home tab. Owning it at the shell level
/// means the hamburger and the notification bell are reachable from all four
/// tabs, and each tab only supplies what changes: its title.
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    required this.onOpenMenu,
    required this.onOpenNotifications,
    this.subtitle,
    this.onTapSubtitle,
    this.greetingName,
    this.unreadNotifications = 0,
  });

  /// Shown when [greetingName] is null. The home tab greets instead.
  final String title;

  /// A first name. When present the title becomes "Merhaba, X 👋".
  final String? greetingName;

  /// The location line under the title, or null for tabs that have none.
  final String? subtitle;
  final VoidCallback? onTapSubtitle;

  final VoidCallback onOpenMenu;
  final VoidCallback onOpenNotifications;

  /// Drives the dot on the bell. Zero means no dot at all — an empty badge is
  /// worse than none, because it implies something is waiting.
  final int unreadNotifications;

  @override
  Widget build(BuildContext context) {
    final name = greetingName?.trim();
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (name != null && name.isNotEmpty)
                  Text(
                    'Merhaba, $name! 👋',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  )
                else
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: onTapSubtitle,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_rounded,
                          size: 14,
                          color: Color(0xFFF43F5E),
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          _CircleButton(
            icon: Icons.notifications_none_rounded,
            iconColor: const Color(0xFF5B4ACD),
            onTap: onOpenNotifications,
            semanticLabel: 'Bildirimler',
            badgeCount: unreadNotifications,
          ),
          const SizedBox(width: 10),
          _CircleButton(
            icon: Icons.menu_rounded,
            iconColor: const Color(0xFF1E293B),
            onTap: onOpenMenu,
            semanticLabel: 'Menü',
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.iconColor,
    required this.onTap,
    required this.semanticLabel,
    this.badgeCount = 0,
  });

  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final String semanticLabel;
  final int badgeCount;

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      Material(
        color: const Color(0xFFF1F5F9),
        shape: const CircleBorder(),
        child: Semantics(
          button: true,
          label: semanticLabel,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: SizedBox(
              width: 42,
              height: 42,
              child: Icon(icon, color: iconColor, size: 20),
            ),
          ),
        ),
      ),
      if (badgeCount > 0)
        Positioned(
          top: -2,
          right: -2,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            constraints: const BoxConstraints(minWidth: 18),
            decoration: BoxDecoration(
              color: const Color(0xFFF43F5E),
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: Colors.white, width: 1.5),
            ),
            child: Text(
              badgeCount > 99 ? '99+' : '$badgeCount',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
    ],
  );
}
