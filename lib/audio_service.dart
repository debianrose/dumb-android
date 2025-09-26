import 'dart:async';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class MyAudioService {
  late FlutterSoundPlayer _audioPlayer;
  final StreamController<void> _playbackCompleteController = StreamController<void>.broadcast();
  
  bool _isPlaying = false;

  Stream<void> get playbackCompleteStream => _playbackCompleteController.stream;

  MyAudioService() {
    _audioPlayer = FlutterSoundPlayer();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    await _audioPlayer.openPlayer();
  }

  Future<void> playRecording(String filePath) async {
    if (_isPlaying) {
      await _audioPlayer.stopPlayer();
    }

    try {
      _isPlaying = true;
      await _audioPlayer.startPlayer(
        fromURI: filePath,
        codec: Codec.aacADTS,
        whenFinished: () {
          _isPlaying = false;
          _playbackCompleteController.add(null);
        },
      );
    } catch (e) {
      print('Error playing recording: $e');
      _isPlaying = false;
    }
  }

  Future<void> stopPlaying() async {
    await _audioPlayer.stopPlayer();
    _isPlaying = false;
  }

  void dispose() {
    _audioPlayer.closePlayer();
    _playbackCompleteController.close();
  }

  bool get isPlaying => _isPlaying;
}
