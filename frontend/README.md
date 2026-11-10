# Vynil — app Flutter

App de música que roda **100% no dispositivo**: você cola um link do YouTube,
o próprio app baixa o áudio e a capa (via `youtube_explode_dart`) e toca
offline, com notificação de mídia e controles. Sem servidor, sem login.

## Recursos

- Baixa o áudio direto do YouTube no aparelho e salva localmente.
- Biblioteca offline com capa, artista e duração.
- Player com fila nativa (avançar/voltar), shuffle, fade na troca de faixa.
- Notificação de mídia (bandeja/lockscreen) com capa e controles.
- Compartilhar um vídeo do YouTube para o app já baixa.
- Atualização automática via GitHub Releases (sideload do APK).

## Rodando

```bash
flutter pub get
flutter run
```

## Build de release

Use o `../release.sh` na raiz do repo (bump de versão + build arm64 + publicação
no GitHub Releases). Para um APK avulso:

```bash
flutter build apk --release --split-per-abi
```

## Armazenamento

As faixas ficam em `getApplicationDocumentsDirectory()/vynil/_default`:

```
music/<id>.<ext>     # áudio baixado
covers/<id>.jpg      # capa
library.json         # índice de metadados (lista de Track)
```
