import 'package:flutter/material.dart';
import 'audio_service.dart';

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
  final AudioService _audioService = AudioService();
  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _startRecording();
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _audioService.dispose();
    super.dispose();
  }

  void _startRecording() async {
    try {
      final path = await _audioService.startRecording();
      if (path != null) {
        setState(() {
          _isRecording = true;
        });
        
        _startTimer();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка записи: $e')),
      );
      widget.onCancel();
    }
  }

  void _startTimer() {
    _recordingDuration = Duration.zero;
    _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _recordingDuration += const Duration(seconds: 1);
      });
      
      // Автоматическое прекращение записи через 2 минуты
      if (_recordingDuration.inMinutes >= 2) {
        _stopRecording();
      }
    });
  }

  void _stopRecording() async {
    _recordingTimer?.cancel();
    
    try {
      final path = await _audioService.stopRecording();
      if (path != null && mounted) {
        widget.onRecordingComplete(path);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сохранения: $e')),
        );
        widget.onCancel();
      }
    }
  }

  void _cancelRecording() async {
    _recordingTimer?.cancel();
    await _audioService.stopRecording();
    widget.onCancel();
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, "0");
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.mic, color: Colors.red),
              SizedBox(width: 8),
              Text(
                'Запись...',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              Spacer(),
              Text(
                _formatDuration(_recordingDuration),
                style: TextStyle(fontFamily: 'monospace', fontSize: 16),
              ),
            ],
          ),
          SizedBox(height: 12),
          LinearProgressIndicator(
            backgroundColor: Colors.red.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
          ),
          SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              ElevatedButton(
                onPressed: _cancelRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey.shade300,
                ),
                child: Row(
                  children: [
                    Icon(Icons.cancel, size: 20),
                    SizedBox(width: 4),
                    Text('Отмена'),
                  ],
                ),
              ),
              ElevatedButton(
                onPressed: _stopRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                child: Row(
                  children: [
                    Icon(Icons.stop, size: 20),
                    SizedBox(width: 4),
                    Text('Отправить'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
