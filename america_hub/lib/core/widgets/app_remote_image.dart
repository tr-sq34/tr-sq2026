import 'package:flutter/material.dart';

import 'app_image_source.dart';

/// Bir gorseli, kaynagi ne olursa olsun ayni sekilde cizer.
///
/// Adi "remote" ama gelen deger her zaman uzak bir adres degil: uye galeriden
/// bir fotograf sectiginde yukleme bitene kadar elimizde yalnizca cihazdaki
/// dosya yolu oluyor. Eskiden burasi sadece `Image.network` kullandigi icin o
/// fotograflar bos bir kare olarak ciziliyordu; artik cozumleme
/// [appImageProvider] uzerinden yapiliyor ve http(s), blob, data ve yerel
/// dosya yollari ayni yerden geciyor.
class AppRemoteImage extends StatelessWidget {
  const AppRemoteImage({
    super.key,
    required this.imageUrl,
    required this.semanticLabel,
    this.fit = BoxFit.cover,
  });

  final String imageUrl;
  final String semanticLabel;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final provider = appImageProvider(imageUrl);
    if (provider == null) return const _ImagePlaceholder();
    return Image(
      image: provider,
      fit: fit,
      semanticLabel: semanticLabel,
      errorBuilder: (context, error, stackTrace) => const _ImagePlaceholder(),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const _ImagePlaceholder(),
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) =>
      const ColoredBox(color: Color(0xFF1E293B));
}
