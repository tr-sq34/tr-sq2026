import 'package:flutter/material.dart';

/// Legacy name retained while the visual system uses flat, light cards.
class AppGlassSurface extends StatelessWidget {
  const AppGlassSurface({super.key, required this.child, this.padding, this.borderRadius = 20});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
          border: Border.all(color: const Color(0xFFF0EEF4)),
          boxShadow: const [BoxShadow(color: Color(0x120E0B18), blurRadius: 18, offset: Offset(0, 7))],
        ),
        child: child,
      );
}
