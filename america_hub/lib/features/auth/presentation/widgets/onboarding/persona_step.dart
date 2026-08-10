import 'package:flutter/material.dart';

import '../../../domain/entities/onboarding_persona.dart';
import 'aurora_surfaces.dart';
import 'onboarding_step_scaffold.dart';

/// Every persona in one wrap, without group headings.
///
/// Two-column cards plus four section labels ran roughly 1400 dp, so the step
/// opened on a fraction of the catalogue and asked people to scroll through the
/// rest. Chips fit the whole list in about a third of that: the personas stay
/// in group order, which keeps related ones adjacent without spending a heading
/// on each.
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
  Widget build(BuildContext context) {
    final personas = [
      for (final group in kOnboardingPersonaGroups) ...group.personas,
    ];

    return OnboardingStepScaffold(
      icon: Icons.auto_awesome_rounded,
      title: 'Sana göre bir\nakış kuralım',
      subtitle:
          'Sana uyan her şeyi seç — ilk seçtiğin, profilinde öne çıkan rolün olur.',
      accent: const Color(0xFF19C29A),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final persona in personas)
              _PersonaChip(
                persona: persona,
                order: selected.indexOf(persona.id),
                // A full basket must still allow deselecting what is in it.
                enabled: selected.contains(persona.id) ||
                    selected.length < kMaxPersonaSelection,
                onTap: () => onToggled(persona.id),
              ),
          ],
        ),
        const SizedBox(height: 18),
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
                    : '${selected.length} / $kMaxPersonaSelection seçildi'
                        ' · ana rolün: ${kOnboardingPersonasById[selected.first]?.label ?? ''}',
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
}

class _PersonaChip extends StatelessWidget {
  const _PersonaChip({
    required this.persona,
    required this.order,
    required this.enabled,
    required this.onTap,
  });

  final OnboardingPersona persona;

  /// Index within the selection, or -1 when unselected. Zero is the primary
  /// role and gets a filled icon so the ordering is visible, not just stated.
  final int order;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final selected = order >= 0;
    return Opacity(
      opacity: enabled ? 1 : .45,
      child: AuroraCard(
        onTap: enabled ? onTap : null,
        selected: selected,
        accent: persona.accent,
        borderRadius: 20,
        padding: const EdgeInsets.fromLTRB(12, 9, 14, 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              order == 0 ? Icons.star_rounded : persona.icon,
              size: 17,
              color: selected ? persona.accent : Colors.white.withValues(alpha: .72),
            ),
            const SizedBox(width: 8),
            // Flexible, not a bare Text: the longest labels are wider than a
            // narrow phone's text column once the system font scale is turned
            // up, and a chip that overflows loses the end of its own name.
            Flexible(
              child: Text(
                persona.label,
                style: AuroraText.body(
                  size: 13.5,
                  weight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
