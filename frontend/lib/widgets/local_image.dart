// ImageProvider de um arquivo local — só no Android/desktop (dart:io).
// No web retorna null (sem acesso a arquivos).
export 'local_image_stub.dart' if (dart.library.io) 'local_image_io.dart';
