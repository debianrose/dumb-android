import 'dart:io';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;

class AudioService {
  final Record _audioRecord = Record();
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _currentRecordingPath;
  bool _isRecording = false;
  bool _isPlaying = false;

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

  Future<String?> startRecording() async {
    if (!await _checkPermissions()) {
      throw Exception('Permissions not granted');
    }

    if (_isRecording) return null;

    try {
      final directory = await getTemporaryDirectory();
      final fileName = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      _currentRecordingPath = '${directory.path}/$fileName';

      await _audioRecord.start(
        path: _currentRecordingPath!,
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        samplingRate: 44100,
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
      final path = await _audioRecord.stop();
      _isRecording = false;
      return path;
    } catch (e) {
      print('Error stopping recording: $e');
      return null;
    }
  }

  Future<void> playRecording(String filePath) async {
    if (_isPlaying) {
      await _audioPlayer.stop();
    }

    try {
      _isPlaying = true;
      await _audioPlayer.setFilePath(filePath);
      await _audioPlayer.play();
      
      _audioPlayer.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          _isPlaying = false;
        }
      });
    } catch (e) {
      print('Error playing recording: $e');
      _isPlaying = false;
    }
  }

  Future<void> stopPlaying() async {
    await _audioPlayer.stop();
    _isPlaying = false;
  }

  Future<void> uploadVoiceMessage(String channelId, String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found');
      }

    } catch (e) {
      print('Error uploading voice message: $e');
      rethrow;
    }
  }

  void dispose() {
    _audioRecord.dispose();
    _audioPlayer.dispose();
  }

  bool get isRecording => _isRecording;
  bool get isPlaying => _isPlaying;
  String? get currentRecordingPath => _currentRecordingPath;
}
