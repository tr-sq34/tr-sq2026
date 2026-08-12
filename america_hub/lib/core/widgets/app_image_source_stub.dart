import 'package:flutter/widgets.dart';

/// Web has no filesystem to read from — `image_picker` hands back a `blob:`
/// URL there, which the network branch already covers.
ImageProvider? localFileImage(String path) => null;
