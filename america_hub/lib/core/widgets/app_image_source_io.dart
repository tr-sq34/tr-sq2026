import 'dart:io';

import 'package:flutter/widgets.dart';

/// A file the member just picked, before any upload has given it a URL.
ImageProvider? localFileImage(String path) => FileImage(File(path));
