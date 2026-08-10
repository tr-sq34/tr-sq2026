import 'package:flutter/material.dart';

import 'aurora_surfaces.dart';

/// Common layout for every onboarding step: badge, headline, supporting line,
/// then the step's own content. Keeps the rhythm identical across steps so the
/// flow feels like one screen changing rather than three unrelated pages.
class OnboardingStepScaffold extends StatelessWidget {
  const OnboardingStepScaffold({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.accent = Colors.white,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final Color accent;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(22, 8, 22, 24),
    physics: const BouncingScrollPhysics(),
    children: [
      AuroraIconBadge(icon: icon, accent: accent),
      const SizedBox(height: 20),
      Text(title, style: AuroraText.title()),
      const SizedBox(height: 10),
      Text(subtitle, style: AuroraText.subtitle()),
      const SizedBox(height: 24),
      ...children,
    ],
  );
}
