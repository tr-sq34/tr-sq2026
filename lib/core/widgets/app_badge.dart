import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class AppBadge extends StatelessWidget {
  const AppBadge({super.key, required this.label, this.color = AppColors.primaryLight, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: color.withValues(alpha: .22), borderRadius: BorderRadius.circular(100), border: Border.all(color: color.withValues(alpha: .45))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, color: color, size: 12), const SizedBox(width: 4)],
          Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: .25)),
        ]),
      );
}
