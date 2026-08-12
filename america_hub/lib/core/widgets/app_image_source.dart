import 'package:flutter/widgets.dart';

import 'app_image_source_stub.dart'
    if (dart.library.io) 'app_image_source_io.dart';

/// Turns a stored image address into something Flutter can actually draw.
///
/// Not every address is a URL. In mock mode an avatar is still sitting in the
/// picker's cache directory as a plain filesystem path, and `NetworkImage`
/// cannot read one of those: it fails quietly, while the caller — seeing a
/// non-empty address — has already hidden its initials fallback. That pairing
/// is why a freshly chosen profile photo looked like it had never been added.
///
/// Returns null when there is nothing drawable, which is the caller's cue to
/// show its placeholder.
ImageProvider? appImageProvider(String? source) {
  final value = source?.trim();
  if (value == null || value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  switch (uri?.scheme) {
    case 'http' || 'https' || 'blob' || 'data':
      return NetworkImage(value);
    case 'file':
      return localFileImage(uri!.toFilePath());
  }
  // Anything left holding a path separator is a file the picker handed us.
  // `C:\...` lands here too: it parses as a one-letter scheme, not a drive.
  if (value.contains('/') || value.contains(r'\')) return localFileImage(value);
  // A bare token is a media id nothing resolved; there is nothing to draw.
  return null;
}
