import 'package:flutter/material.dart';

class AppRemoteImage extends StatelessWidget {
  const AppRemoteImage({super.key, required this.imageUrl, required this.semanticLabel, this.fit = BoxFit.cover});

  final String imageUrl;
  final String semanticLabel;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final uri = Uri.tryParse(imageUrl);
    if (imageUrl.trim().isEmpty || uri == null || !uri.hasAbsolutePath) {
      return const ColoredBox(color: Color(0xFF1E293B));
    }
    return Image.network(
      imageUrl,
      fit: fit,
      semanticLabel: semanticLabel,
      errorBuilder: (context, error, stackTrace) => const ColoredBox(color: Color(0xFF1E293B)),
      loadingBuilder: (context, child, progress) => progress == null ? child : const ColoredBox(color: Color(0xFF1E293B)),
    );
  }
}
