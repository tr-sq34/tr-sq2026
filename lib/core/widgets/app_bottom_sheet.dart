import 'package:flutter/material.dart';

import '../constants/app_colors.dart';
import '../design/app_radius.dart';

Future<T?> showAppBottomSheet<T>({required BuildContext context, required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: AppRadius.sheet),
      ),
      child: SafeArea(top: false, child: child),
    ),
  );
}
