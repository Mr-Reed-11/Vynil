import 'dart:io';

import 'package:flutter/widgets.dart';

/// Android/desktop: provê a capa salva no dispositivo como imagem.
ImageProvider? localImage(String? path) {
  if (path == null) return null;
  final file = File(path);
  return file.existsSync() ? FileImage(file) : null;
}
