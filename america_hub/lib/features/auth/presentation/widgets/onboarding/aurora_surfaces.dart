import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Shared type ramp for the onboarding flow. Inter, matching the login screen,
/// so the whole auth journey reads as one product rather than three.
class AuroraText {
  const AuroraText._();

  static TextStyle title() => GoogleFonts.inter(
    fontSize: 29,
    height: 1.18,
    fontWeight: FontWeight.w800,
    color: Colors.white,
    letterSpacing: -0.6,
  );

  static TextStyle subtitle() => GoogleFonts.inter(
    fontSize: 15,
    height: 1.45,
    fontWeight: FontWeight.w400,
    color: Colors.white.withValues(alpha: .70),
  );

  static TextStyle sectionLabel() => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.9,
    color: Colors.white.withValues(alpha: .55),
  );

  static TextStyle body({
    double size = 15,
    FontWeight weight = FontWeight.w600,
    double alpha = 1,
  }) => GoogleFonts.inter(
    fontSize: size,
    fontWeight: weight,
    color: Colors.white.withValues(alpha: alpha),
  );
}

/// Frosted panel used for every input surface on the dark backdrop.
class AuroraCard extends StatelessWidget {
  const AuroraCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 22,
    this.selected = false,
    this.accent,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final bool selected;
  final Color? accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final highlight = accent ?? Colors.white;
    final radius = BorderRadius.circular(borderRadius);
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: selected
                ? highlight.withValues(alpha: .22)
                : Colors.white.withValues(alpha: .09),
            borderRadius: radius,
            border: Border.all(
              color: selected
                  ? highlight.withValues(alpha: .85)
                  : Colors.white.withValues(alpha: .16),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              splashColor: highlight.withValues(alpha: .12),
              child: Padding(padding: padding, child: child),
            ),
          ),
        ),
      ),
    );
  }
}

/// Rounded icon badge that heads each step and each persona card.
class AuroraIconBadge extends StatelessWidget {
  const AuroraIconBadge({
    super.key,
    required this.icon,
    this.size = 56,
    this.accent = Colors.white,
    this.filled = false,
  });

  final IconData icon;
  final double size;
  final Color accent;
  final bool filled;

  @override
  Widget build(BuildContext context) => AnimatedContainer(
    duration: const Duration(milliseconds: 180),
    height: size,
    width: size,
    decoration: BoxDecoration(
      color: filled ? accent : accent.withValues(alpha: .16),
      borderRadius: BorderRadius.circular(size * 0.32),
      border: Border.all(color: accent.withValues(alpha: filled ? 1 : .35)),
      boxShadow: filled
          ? [BoxShadow(color: accent.withValues(alpha: .40), blurRadius: 18, offset: const Offset(0, 6))]
          : null,
    ),
    child: Icon(
      icon,
      size: size * 0.46,
      color: filled ? const Color(0xFF12102A) : Colors.white,
    ),
  );
}

/// Text field styled for the dark backdrop. The app-wide [AppTextField] draws a
/// light grey filled box that disappears against the Aurora gradient.
class AuroraTextField extends StatelessWidget {
  const AuroraTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.prefixIcon,
    this.suffix,
    this.keyboardType,
    this.textCapitalization = TextCapitalization.words,
    this.onChanged,
    this.onSubmitted,
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData? prefixIcon;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: .18)),
    );
    return TextField(
      controller: controller,
      focusNode: focusNode,
      autofocus: autofocus,
      keyboardType: keyboardType,
      textCapitalization: textCapitalization,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      cursorColor: Colors.white,
      style: AuroraText.body(size: 16, weight: FontWeight.w600),
      decoration: InputDecoration(
        filled: true,
        fillColor: Colors.white.withValues(alpha: .09),
        hintText: hintText,
        hintStyle: AuroraText.body(size: 15, weight: FontWeight.w400, alpha: .45),
        prefixIcon: prefixIcon == null
            ? null
            : Icon(prefixIcon, color: Colors.white.withValues(alpha: .60), size: 21),
        suffixIcon: suffix,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border,
        enabledBorder: border,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: .70), width: 1.4),
        ),
      ),
    );
  }
}
