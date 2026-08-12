import 'package:flutter/material.dart';

abstract final class AppColors {
  static const background = Color(0xFFF9F9FB);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceBorder = Color(0xFFEAE8F0);
  static const canvas = Color(0xFFF3F1F7);
  static const primary = Color(0xFF6C5CE7);
  static const primaryLight = Color(0xFF7C6CF1);
  static const accentEmerald = Color(0xFF16A085);
  static const accentRose = Color(0xFFE87393);
  static const accentAmber = Color(0xFFE8A33A);
  // The profile reads as a calmer place than the feed: Aurora's purple thins
  // out into a wash behind the header, and cards are separated by a hairline
  // instead of a shadow. Same palette, lower volume - not a second theme.
  static const profileTint = Color(0xFFF5F3FF);
  static const profileBorder = Color(0xFFE9E6F5);
  static const profileAccent = Color(0xFF5B4ACD);
  static const textPrimary = Color(0xFF111111);
  static const textSecondary = Color(0xFF686473);
  static const textMuted = Color(0xFF9893A2);
}
