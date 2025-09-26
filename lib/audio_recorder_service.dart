import 'dart:io';
import 'dart:async';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class AudioRecorderService {
  late FlutterSoundRecorder _recorder;
  late FlutterSoundPlayer _player;
  String? _currentRecordingPath;
  bool _isRecording = false;
  bool _isPlaying = false;

  AudioRecorderService() {
    _recorder = FlutterSoundRecorder();
    _player = FlutterSoundPlayer();
  }

  Future<bool> _checkPermissions() async {
    final micStatus = await Permission.microphone.status;
    final storageStatus = await Permission.storage.status;
    
    if (!micStatus.isGranted) {
      await Permission.microphone.request();
    }
    if (!storageStatus.isGranted) {
      await Permission.storage.request();
    }
    
    return micStatus.isGranted && storageStatus.isGranted;
  }

  Future<void> initialize() async {
    await _recorder.openRecorder();
    await _player.openPlayer();
  }

  Future<String?> startRecording() async {
    if (!await _checkPermissions()) {
      return null;
    }

    try {
      final directory = await getTemporaryDirectory();
      final fileName = 'recording_${DateTime.now().millisecondsSinceEpoch}.aac';
      _currentRecordingPath = '${directory.path}/$fileName';
      
      await _recorder.startRecorder(
        toFile: _currentRecordingPath,
        codec: Codec.aacADTS,
      );
      
      _isRecording = true;
      return _currentRecordingPath;
    } catch (e) {
      print('Error starting recording: $e');
      return null;
    }
  }

  Future<String?> stopRecording() async {
    if (!_isRecording) return null;
    
    try {
      await _recorder.stopRecorder();
      _isRecording = false;
      return _currentRecordingPath;
    } catch (e) {
      print('Error stopping recording: $e');
      return null;
    }
  }

  Future<void> playRecording(String filePath) async {
    if (_isPlaying) {
      await stopPlaying();
    }

    try {
      _isPlaying = true;
      await _player.startPlayer(
        fromURI: filePath,
        codec: Codec.aacADTS,
        whenFinished: () {
          _isPlaying = false;
        },
      );
    } catch (e) {
      print('Error playing recording: $e');
      _isPlaying = false;
    }
  }

  Future<void> stopPlaying() async {
    await _player.stopPlayer();
    _isPlaying = false;
  }

  // Исправленный метод - используем правильный тип
  Stream<RecordingDisposition> get recordingProgress => _recorder.onProgress!;

  Future<void> dispose() async {
    await _recorder.closeRecorder();
    await _player.closePlayer();
  }

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
}
