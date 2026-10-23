// Seleciona a implementação certa por plataforma: no Android/desktop usa
// dart:io (baixa o arquivo e abre o instalador); no web usa o stub, que
// mantém o build compilável sem dart:io.
export 'apk_installer_stub.dart'
    if (dart.library.io) 'apk_installer_io.dart';
