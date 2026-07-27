import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../design/app_radius.dart';

enum AppButtonVariant { primary, secondary, text }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final child = isLoading
        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
        : icon == null
            ? Text(label)
            : Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 19), const SizedBox(width: 8), Text(label)]);

    return switch (variant) {
      AppButtonVariant.primary => DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primaryLight, AppColors.primary]),
            borderRadius: const BorderRadius.all(AppRadius.button),
            boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: .30), blurRadius: 16, offset: const Offset(0, 6))],
          ),
          child: ElevatedButton(
            onPressed: isLoading ? null : onPressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white,
              shadowColor: Colors.transparent,
            ),
            child: child,
          ),
        ),
      AppButtonVariant.secondary => OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.textPrimary),
          child: child,
        ),
      AppButtonVariant.text => TextButton(
          onPressed: isLoading ? null : onPressed,
          child: child,
        ),
    };
  }
}
