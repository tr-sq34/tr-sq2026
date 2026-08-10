import 'package:flutter/material.dart';

import '../../../../core/constants/app_colors.dart';
import '../../domain/entities/user_profile.dart';

/// Tier is carried by colour and border weight, never by colour alone: a
/// legendary badge also gets a thicker ring and a filled glyph, so the ladder
/// still reads for a member who cannot tell violet from amber.
({Color fill, Color border, Color ink, IconData icon, double weight}) badgeTierStyle(
  BadgeTier tier,
) => switch (tier) {
  BadgeTier.bronze => (
    fill: const Color(0xFFF6F1EA),
    border: const Color(0xFFD8C3A5),
    ink: const Color(0xFF8A6A3F),
    icon: Icons.workspace_premium_outlined,
    weight: 1,
  ),
  BadgeTier.silver => (
    fill: const Color(0xFFF2F4F8),
    border: const Color(0xFFB9C2D0),
    ink: const Color(0xFF5A6577),
    icon: Icons.workspace_premium_rounded,
    weight: 1.4,
  ),
  BadgeTier.gold => (
    fill: const Color(0xFFFFF7E3),
    border: const Color(0xFFE8C05A),
    ink: const Color(0xFF9A7212),
    icon: Icons.military_tech_rounded,
    weight: 1.8,
  ),
  BadgeTier.legendary => (
    fill: const Color(0xFFF3EEFF),
    border: AppColors.profileAccent,
    ink: AppColors.profileAccent,
    icon: Icons.auto_awesome_rounded,
    weight: 2.2,
  ),
};

String badgeTierLabel(BadgeTier tier) => switch (tier) {
  BadgeTier.bronze => 'Bronz',
  BadgeTier.silver => 'Gümüş',
  BadgeTier.gold => 'Altın',
  BadgeTier.legendary => 'Elmas',
};

/// The showcase pill used on the profile header and next to a member's name.
class ProfileBadgeChip extends StatelessWidget {
  const ProfileBadgeChip({
    super.key,
    required this.title,
    required this.tier,
    this.locked = false,
    this.onTap,
  });

  final String title;
  final BadgeTier tier;
  final bool locked;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = badgeTierStyle(tier);
    return Semantics(
      label: '$title, ${badgeTierLabel(tier)} rozet${locked ? ', kilitli' : ''}',
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: locked ? AppColors.canvas : style.fill,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: locked ? AppColors.surfaceBorder : style.border,
              width: locked ? 1 : style.weight,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                locked ? Icons.lock_outline : style.icon,
                size: 14,
                color: locked ? AppColors.textMuted : style.ink,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: locked ? AppColors.textMuted : style.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
