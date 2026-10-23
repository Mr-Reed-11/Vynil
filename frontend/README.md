# Music Server — app Flutter

App para navegar na biblioteca do
[music-server](../backend/README.md), adicionar links do YouTube, acompanhar o download
e tocar as músicas direto do servidor.

## Funcionalidades

- Lista as faixas do servidor com capa, artista e duração.
- Adiciona um link do YouTube (com botão para colar da área de transferência).
- Atualiza o progresso automaticamente enquanto há downloads na fila.
- Player com play/pause, seek, avançar/voltar 10 s e fechar.
- Busca por título/artista, atualização por pull-to-refresh e exclusão de faixas.
- Repetição de downloads com erro.

## Requisitos

- Flutter 3.47+ (Dart 3.13+). Neste ambiente: `~/.local/flutter/bin/flutter`.
- Backend rodando (`cd ../backend && npm run start:dev`) em `http://localhost:3000`.

## Rodando

```bash
cd frontend
flutter pub get
flutter run -d chrome      # web
# ou
flutter run                # dispositivo/emulador conectado
```

O app escolhe a URL do backend automaticamente:

| Plataforma | URL padrão |
| --- | --- |
| Web / Linux / iOS Simulator | `http://localhost:3000` |
| Emulador Android | `http://10.0.2.2:3000` |

Para celular físico, use o IP da máquina na rede local:

```bash
flutter run --dart-define=API_BASE_URL=http://192.168.0.10:3000
```

Se o backend estiver com `APP_API_KEY` definida:

```bash
flutter run --dart-define=API_KEY=minha-chave
# combinando:
flutter run \
  --dart-define=API_BASE_URL=http://192.168.0.10:3000 \
  --dart-define=API_KEY=minha-chave
```

## Build web

```bash
flutter build web --release
# os arquivos ficam em build/web
```

Para gerar o web build já apontando para um servidor remoto:

```bash
flutter build web --release \
  --dart-define=API_BASE_URL=http://192.168.0.10:3000
```

## Estrutura

```
lib/
├── main.dart                 # providers + configuração de áudio
├── app.dart                  # MaterialApp
├── core/
│   ├── app_config.dart       # URL do backend e API key
│   ├── format.dart           # duração e tamanho
│   └── theme.dart            # tema Material 3 escuro
├── data/
│   ├── track.dart            # modelo/status da faixa
│   └── music_api.dart        # cliente HTTP da API
├── controllers/
│   ├── library_controller.dart  # lista, busca, polling, ações
│   └── player_controller.dart   # just_audio
├── screens/
│   └── library_screen.dart
└── widgets/
    ├── add_track_sheet.dart
    ├── cover_art.dart
    ├── player_bar.dart
    └── track_tile.dart
```

## Validação

```bash
flutter analyze
flutter test
flutter build web --release
```

## Limitações atuais

- Sem download offline no dispositivo (o áudio é sempre transmitido).
- Sem reprodução em segundo plano/controles na notificação (`audio_service`).
- `just_audio` não tem implementação oficial para Linux; priorize Android, iOS
  ou web.
- O Android usa `usesCleartextTraffic` e o iOS libera ATS **apenas para
  desenvolvimento** com HTTP local. Em produção, sirva a API por HTTPS e remova
  essas exceções.
- Build Android/iOS não foi executado neste ambiente por falta do Android SDK /
  Xcode; a compilação web foi validada.
