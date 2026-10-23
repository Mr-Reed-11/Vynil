package com.reed.musicserver.music_server_app

import com.ryanheise.audioservice.AudioServiceActivity

// Precisa estender AudioServiceActivity para o just_audio_background/audio_service
// conseguir anexar o FlutterEngine ao serviço de mídia (notificação/lockscreen).
class MainActivity : AudioServiceActivity()
