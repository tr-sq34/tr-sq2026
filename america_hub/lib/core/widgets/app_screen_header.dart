import 'package:flutter/material.dart';

import '../constants/app_colors.dart';

class AppScreenHeader extends StatelessWidget {
  const AppScreenHeader({super.key, required this.title, required this.subtitle, this.action});

  final String title;
  final String subtitle;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppColors.textPrimary, fontSize: 25, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
          ]),
        ),
        if (action case final Widget action) action,
      ]),
    );
  }
}
