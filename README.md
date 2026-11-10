# Vynil

App de música pessoal que roda **100% no dispositivo**: você cola um link do
YouTube, o próprio app baixa o áudio e a capa (via `youtube_explode_dart`) e
toca offline, com notificação de mídia e controles. Sem servidor, sem login.

> ⚠️ **Uso responsável:** baixe apenas conteúdo que você tem direito de usar.
> Este é um projeto pessoal de estudo; respeite os Termos de Serviço do YouTube
> e a legislação de direitos autorais do seu país.

## Stack

- **Flutter** + just_audio / just_audio_background / audio_service
- **provider** (estado)
- **youtube_explode_dart** (extração/download no próprio aparelho)
- Armazenamento local em `getApplicationDocumentsDirectory()/vynil`

## Rodando

```bash
cd frontend
flutter pub get
flutter run
```

## Publicando uma versão (GitHub Releases)

O app se atualiza sozinho: na abertura ele consulta o último release público em
`github.com/Mr-Reed-11/Vynil/releases`, compara a versão (tag `vX.Y.Z`) com a
instalada e, se houver nova, baixa e instala o APK (sideload).

Para publicar, na raiz do repo:

```bash
./release.sh 1.5.0 "Notas da versão"
```

O script faz o bump do `pubspec.yaml`, builda o APK arm64, commita/empurra e
cria o release no GitHub com o APK anexado (asset `vynil-<versao>-arm64.apk`).

## Licença

MIT
