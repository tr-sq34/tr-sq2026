import 'package:flutter/material.dart';

/// Yazıdan ibaret bir paylaşımın ızgaradaki yüzü.
///
/// Fotoğrafsız paylaşımlar ızgarayı gri kutular dizisine çeviriyordu: aynı
/// renkte on kare, hiçbiri diğerinden ayırt edilemiyor. Renk paylaşımın
/// kimliğinden türetiliyor, rastgele değil - aynı paylaşım her açılışta aynı
/// renkte duruyor, yoksa ızgara her yenilemede başka bir tabloya dönerdi.
const _palettes = <List<Color>>[
  [Color(0xFF6D28D9), Color(0xFF9333EA)],
  [Color(0xFF0F766E), Color(0xFF14B8A6)],
  [Color(0xFFB45309), Color(0xFFF59E0B)],
  [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
  [Color(0xFFBE123C), Color(0xFFF43F5E)],
  [Color(0xFF15803D), Color(0xFF4ADE80)],
];

LinearGradient postCardGradient(String postId) {
  var hash = 0;
  for (final unit in postId.codeUnits) {
    hash = (hash * 31 + unit) & 0x7FFFFFFF;
  }
  final colors = _palettes[hash % _palettes.length];
  return LinearGradient(
    colors: colors,
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}
