import 'package:flutter/material.dart';

import '../../../domain/entities/onboarding_persona.dart';
import 'aurora_surfaces.dart';
import 'onboarding_step_scaffold.dart';

class PersonaStep extends StatelessWidget {
  const PersonaStep({
    super.key,
    required this.selected,
    required this.onToggled,
  });

  /// Persona ids in the order they were picked — the first one decides
  /// `primaryIntent`, so order is meaningful and must be preserved.
  final List<String> selected;
  final ValueChanged<String> onToggled;

  @override
  Widget build(BuildContext context) => OnboardingStepScaffold(
    icon: Icons.auto_awesome_rounded,
    title: 'Bu toplulukta\nsen kimsin?',
    subtitle:
        'Seni tanıyan bir akış kurabilmemiz için sana uyan her şeyi seç. '
        'İlk seçtiğin, profilinde öne çıkan rolün olur.',
    accent: const Color(0xFF19C29A),
    children: [
      for (final group in kOnboardingPersonaGroups) ...[
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(group.title.toUpperCase(), style: AuroraText.sectionLabel()),
        ),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          // Tall enough that a two-line label plus the "Ana rolün" caption on
          // the primary pick still fits on a 360 dp phone.
          childAspectRatio: 1.14,
          children: [
            for (final persona in group.personas)
              _PersonaCard(
                persona: persona,
                order: selected.indexOf(persona.id),
                // A full basket must still allow deselecting what is in it.
                enabled: selected.contains(persona.id) ||
                    selected.length < kMaxPersonaSelection,
                onTap: () => onToggled(persona.id),
              ),
          ],
        ),
        const SizedBox(height: 24),
      ],
      Row(
        children: [
          Icon(
            selected.isEmpty ? Icons.info_outline_rounded : Icons.check_circle_rounded,
            size: 17,
            color: Colors.white.withValues(alpha: selected.isEmpty ? .55 : .85),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              selected.isEmpty
                  ? 'Devam etmek için en az bir tane seç.'
                  : '${selected.length} / $kMaxPersonaSelection seçildi',
              style: AuroraText.body(
                size: 13,
                weight: FontWeight.w600,
                alpha: selected.isEmpty ? .6 : .85,
              ),
            ),
          ),
        ],
      ),
    ],
  );
}

class _PersonaCard extends StatelessWidget {
  const _PersonaCard({
    required this.persona,
    required this.order,
    required this.enabled,
    required this.onTap,
  });

  final OnboardingPersona persona;

  /// Index within the selection, or -1 when unselected. Zero earns the
  /// "ana rolün" badge.
  final int order;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = order >= 0;
    return AnimatedScale(
      scale: selected ? 1.0 : 0.985,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      child: Opacity(
        opacity: enabled ? 1 : .45,
        child: AuroraCard(
          onTap: enabled ? onTap : null,
          selected: selected,
          accent: persona.accent,
          borderRadius: 20,
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  AuroraIconBadge(
                    icon: persona.icon,
                    size: 40,
                    accent: persona.accent,
                    filled: selected,
                  ),
                  const Spacer(),
                  if (selected)
                    Icon(Icons.check_circle_rounded, size: 20, color: persona.accent),
                ],
              ),
              const Spacer(),
              // Flexible so a long label gives way to the ellipsis instead of
              // pushing the caption past the bottom edge at large text scales.
              Flexible(
                child: Text(
                  persona.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AuroraText.body(
                    size: 13.5,
                    weight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
              if (order == 0) ...[
                const SizedBox(height: 4),
                Text(
                  'Ana rolün',
                  style: AuroraText.body(size: 11, weight: FontWeight.w600, alpha: .7),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
