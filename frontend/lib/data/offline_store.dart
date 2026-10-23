// Seleciona a implementação por plataforma: Android/desktop usam dart:io
// (arquivos locais); web usa o stub (tudo no-op) para manter o build.
export 'offline_store_stub.dart'
    if (dart.library.io) 'offline_store_io.dart';
