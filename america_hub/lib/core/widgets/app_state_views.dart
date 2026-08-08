import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import 'app_button.dart';

class AppLoadingView extends StatelessWidget {
  const AppLoadingView({super.key, this.label = 'Loading…'});
  final String label;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 28, width: 28, child: CircularProgressIndicator(strokeWidth: 2.5)),
          const SizedBox(height: 14),
          Text(label, style: const TextStyle(color: AppColors.textSecondary)),
        ]),
      );
}

class AppEmptyState extends StatelessWidget {
  const AppEmptyState({super.key, required this.icon, required this.title, required this.message, this.actionLabel, this.onAction});
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: AppColors.primaryLight, size: 48),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.textSecondary, height: 1.45)),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              AppButton(label: actionLabel!, onPressed: onAction),
            ],
          ]),
        ),
      );
}

class AppErrorState extends StatelessWidget {
  const AppErrorState({super.key, required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => AppEmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Something went wrong',
        message: message,
        actionLabel: 'Try Again',
        onAction: onRetry,
      );
}
