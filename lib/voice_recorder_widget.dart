import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'audio_recorder_service.dart';

class VoiceRecorderWidget extends StatefulWidget {
  final Function(String) onRecordingComplete;
  final Function() onCancel;

  const VoiceRecorderWidget({
    super.key,
    required this.onRecordingComplete,
    required this.onCancel,
  });

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget> {
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  bool _isRecording = false;
  List<double> _audioLevels = [];
  late AudioRecorderService _recorderService;
  StreamSubscription? _recordingSubscription;

  @override
  void initState() {
    super.initState();
    _recorderService = AudioRecorderService();
    _initializeRecorder();
  }

  Future<void> _initializeRecorder() async {
    await _recorderService.initialize();
    _startRecording();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _recordingSubscription?.cancel();
    _recorderService.dispose();
    super.dispose();
  }

  void _startRecording() async {
    final filePath = await _recorderService.startRecording();
    if (filePath == null) {
      widget.onCancel();
      return;
    }

    setState(() {
      _isRecording = true;
    });
    
    _startTimer();
    _startAudioLevelMonitoring();
    
    // Слушаем прогресс записи
    _recordingSubscription = _recorderService.recordingProgress.listen((disposition) {
      // Используем реальные данные для визуализации
      if (mounted) {
        setState(() {
          // Преобразуем данные прогресса в уровни звука
          final level = (disposition.decibels ?? 0).abs() / 100; // Пример преобразования
          _audioLevels = List.generate(8, (index) => level.clamp(0.1, 1.0));
        });
      }
    });
  }

  void _startAudioLevelMonitoring() {
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isRecording) {
        timer.cancel();
        return;
      }
      
      // Резервный вариант, если данные прогресса не приходят
      if (_audioLevels.isEmpty && mounted) {
        setState(() {
          _audioLevels = List.generate(8, (index) => Random().nextDouble() * 0.8 + 0.2);
        });
      }
    });
  }

  void _startTimer() {
    _recordingDuration = Duration.zero;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _recordingDuration += const Duration(seconds: 1);
        });
      }
      
      if (_recordingDuration.inMinutes >= 2) {
        _stopRecording();
      }
    });
  }

  void _stopRecording() async {
    _recordingTimer?.cancel();
    _recordingSubscription?.cancel();
    
    final filePath = await _recorderService.stopRecording();
    if (filePath != null) {
      widget.onRecordingComplete(filePath);
    } else {
      widget.onCancel();
    }
  }

  void _cancelRecording() {
    _recordingTimer?.cancel();
    _recordingSubscription?.cancel();
    _recorderService.stopRecording();
    widget.onCancel();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  Widget _buildAudioVisualizer() {
    return Container(
      height: 40,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: List.generate(8, (index) {
          final height = _audioLevels.isNotEmpty && index < _audioLevels.length
              ? 2.0 + (_audioLevels[index] * 30)
              : 2.0;
          
          return Container(
            width: 3,
            height: height,
            margin: const EdgeInsets.symmetric(horizontal: 1.5),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildAudioVisualizer(),
          
          const SizedBox(height: 16),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.circle, color: Colors.red, size: 12),
              const SizedBox(width: 8),
              Text(
                'Запись...',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.red.shade800,
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _formatDuration(_recordingDuration),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.red.shade800,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          LinearProgressIndicator(
            value: _recordingDuration.inSeconds / 120,
            backgroundColor: Colors.red.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
          ),
          
          const SizedBox(height: 20),
          
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _cancelRecording,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade400),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cancel, size: 20),
                      SizedBox(width: 8),
                      Text('Отмена'),
                    ],
                  ),
                ),
              ),
              
              const SizedBox(width: 16),
              
              Expanded(
                child: ElevatedButton(
                  onPressed: _stopRecording,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.stop, size: 20),
                      SizedBox(width: 8),
                      Text('Отправить'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
