import 'package:flutter/material.dart';

/// Segmented progress rail: one bar per step, the active one filling as the
/// step gets answered. Reads at a glance how much is left.
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({
    super.key,
    required this.stepCount,
    required this.currentStep,
  });

  final int stepCount;
  final int currentStep;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      for (var index = 0; index < stepCount; index++) ...[
        if (index > 0) const SizedBox(width: 7),
        Expanded(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            height: 5,
            decoration: BoxDecoration(
              color: index <= currentStep
                  ? Colors.white.withValues(alpha: index == currentStep ? .95 : .55)
                  : Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ],
    ],
  );
}
