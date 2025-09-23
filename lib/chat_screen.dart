import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';
import 'voice_service.dart';

class Message {
  final String id;
  final String from;
  final String text;
  final int timestamp;
  final String channel;
  final VoiceAttachment? voice;

  Message({
    required this.id,
    required this.from,
    required this.text,
    required this.timestamp,
    required this.channel,
    this.voice,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    VoiceAttachment? voice;
    if (json['voice'] != null) {
      voice = VoiceAttachment.fromJson(json['voice']);
    }
    
    return Message(
      id: json['id'] ?? '',
      from: json['from'] ?? '',
      text: json['text'] ?? '',
      timestamp: json['ts'] ?? 0,
      channel: json['channel'] ?? '',
      voice: voice,
    );
  }
}

class VoiceAttachment {
  final String filename;
  final int duration;
  final String downloadUrl;

  VoiceAttachment({
    required this.filename,
    required this.duration,
    required this.downloadUrl,
  });

  factory VoiceAttachment.fromJson(Map<String, dynamic> json) {
    return VoiceAttachment(
      filename: json['filename'] ?? '',
      duration: json['duration'] ?? 0,
      downloadUrl: json['downloadUrl'] ?? '',
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String token;
  final String username;
  final String channelId;
  final String channelName;

  ChatScreen({
    required this.token,
    required this.username,
    required this.channelId,
    required this.channelName,
  });

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final List<Message> _messages = [];
  final AudioPlayer _audioPlayer = AudioPlayer();
  final VoiceService _voiceService = VoiceService();
  
  bool _isRecording = false;
  bool _isLoading = false;
  bool _isLoadingMessages = false;
  String? _currentPlayingMessageId;
  int _currentPosition = 0;
  int _voiceDuration = 0;

  @override
  void initState() {
    super.initState();
    _initializeServices();
    _loadMessages();
    _startMessageRefresh();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    _voiceService.dispose();
    super.dispose();
  }

  Future<void> _initializeServices() async {
    await _voiceService.init();
  }

  Future<void> _loadMessages() async {
    if (_isLoadingMessages) return;
    
    setState(() {
      _isLoadingMessages = true;
    });

    try {
      final response = await http.get(
        Uri.parse('http://95.81.122.186:3000/api/messages?channel=${widget.channelId}&limit=100'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
        },
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        final messagesArray = result['messages'] as List?;
        if (messagesArray != null) {
          final newMessages = messagesArray.map((msgJson) => Message.fromJson(msgJson)).toList();
          
          if (_messages.length != newMessages.length) {
            setState(() {
              _messages.clear();
              _messages.addAll(newMessages);
            });
          }
        }
      } else {
        _showError(result['error'] ?? 'Failed to load messages');
      }
    } catch (e) {
      _showError('Failed to load messages: ${e.toString()}');
    } finally {
      setState(() {
        _isLoadingMessages = false;
      });
    }
  }

  void _startMessageRefresh() {
    Future.delayed(Duration(seconds: 3), () {
      if (mounted) {
        _loadMessages();
        _startMessageRefresh();
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    
    if (text.isEmpty) {
      _showError('Please enter message');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/message'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({
          'channel': widget.channelId,
          'text': text,
        }),
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        _messageController.clear();
        _loadMessages();
        _showSuccess('Message sent');
      } else {
        _showError(result['error'] ?? 'Failed to send message');
      }
    } catch (e) {
      _showError('Failed to send message: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleVoiceRecording() async {
    if (!_isRecording) {
      await _startRecording();
    } else {
      await _stopRecording();
    }
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      _showError('Microphone permission required');
      return;
    }

    try {
      final recordingPath = await _voiceService.startRecording();
      if (recordingPath != null) {
        setState(() {
          _isRecording = true;
        });
        _showSuccess('Recording started...');
      } else {
        _showError('Failed to start recording');
      }
    } catch (e) {
      _showError('Failed to start recording: ${e.toString()}');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final duration = await _voiceService.stopRecording();
      if (duration != null && _voiceService.currentRecordingPath != null) {
        await _uploadVoiceMessage(_voiceService.currentRecordingPath!, duration);
      }
      
      setState(() {
        _isRecording = false;
      });
    } catch (e) {
      _showError('Failed to stop recording: ${e.toString()}');
      setState(() {
        _isRecording = false;
      });
    }
  }

  Future<void> _uploadVoiceMessage(String filePath, Duration duration) async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Получаем voiceId для загрузки
      final initResponse = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/voice/upload'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({
          'channel': widget.channelId,
          'duration': duration.inSeconds,
        }),
      );

      final initResult = json.decode(initResponse.body);
      
      if (initResult['success'] != true) {
        throw Exception('Failed to get upload URL');
      }

      final voiceId = initResult['voiceId'];
      final uploadUrl = 'http://95.81.122.186:3000/api/upload/voice/$voiceId';

      // 2. Загружаем файл
      final request = http.MultipartRequest('POST', Uri.parse(uploadUrl))
        ..headers['Authorization'] = 'Bearer ${widget.token}'
        ..files.add(await http.MultipartFile.fromPath('voice', filePath));

      final uploadResponse = await request.send();
      
      if (uploadResponse.statusCode != 200) {
        throw Exception('Upload failed with status ${uploadResponse.statusCode}');
      }

      // 3. Отправляем сообщение с голосовой записью
      final messageResponse = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/message'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({
          'channel': widget.channelId,
          'text': '[Voice message]',
          'voiceMessage': voiceId,  // Ключ исправлен на voiceMessage
        }),
      );

      final messageResult = json.decode(messageResponse.body);
      
      if (messageResult['success'] == true) {
        _loadMessages();
        _showSuccess('Voice message sent');
      } else {
        _showError('Failed to send voice message: ${messageResult['error']}');
      }
    } catch (e) {
      _showError('Failed to upload voice message: ${e.toString()}');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleVoiceMessage(Message message) async {
    if (_currentPlayingMessageId == message.id) {
      await _stopVoicePlayback();
    } else {
      await _playVoiceMessage(message);
    }
  }

  Future<void> _playVoiceMessage(Message message) async {
    if (message.voice == null) return;

    await _stopVoicePlayback();

    setState(() {
      _currentPlayingMessageId = message.id;
      _voiceDuration = message.voice!.duration * 1000;
    });

    try {
      final url = 'http://95.81.122.186:3000${message.voice!.downloadUrl}';
      await _audioPlayer.play(UrlSource(url));
      
      _audioPlayer.onPositionChanged.listen((Duration duration) {
        if (mounted) {
          setState(() {
            _currentPosition = duration.inMilliseconds;
          });
        }
      });

      _audioPlayer.onPlayerComplete.listen((_) {
        if (mounted) {
          _stopVoicePlayback();
        }
      });

    } catch (e) {
      _showError('Failed to play voice message');
      setState(() {
        _currentPlayingMessageId = null;
      });
    }
  }

  Future<void> _stopVoicePlayback() async {
    await _audioPlayer.stop();
    if (mounted) {
      setState(() {
        _currentPlayingMessageId = null;
        _currentPosition = 0;
      });
    }
  }

  int _getVoiceProgress(String messageId) {
    if (_currentPlayingMessageId == messageId && _voiceDuration > 0) {
      return (_currentPosition * 100 ~/ _voiceDuration);
    }
    return 0;
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _showSuccess(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0:00';
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _buildMessageBubble(Message message) {
    final isOwnMessage = message.from == widget.username;
    final isPlaying = _currentPlayingMessageId == message.id;
    final progress = _getVoiceProgress(message.id);

    return Container(
      margin: EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        mainAxisAlignment: isOwnMessage ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isOwnMessage) 
            CircleAvatar(
              radius: 16,
              child: Text(message.from[0].toUpperCase()),
            ),
          
          Flexible(
            child: Container(
              padding: EdgeInsets.all(12),
              margin: EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: isOwnMessage ? Colors.blue[100] : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (!isOwnMessage)
                    Text(
                      message.from,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                  
                  if (message.text.isNotEmpty && message.text != '[Voice message]')
                    Text(message.text),
                  
                  if (message.voice != null) ...[
                    SizedBox(height: 8),
                    Container(
                      padding: EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.blue,
                            ),
                            onPressed: () => _toggleVoiceMessage(message),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                LinearProgressIndicator(
                                  value: progress / 100.0,
                                  backgroundColor: Colors.grey[300],
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  _formatDuration(message.voice!.duration),
                                  style: TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  
                  SizedBox(height: 4),
                  Text(
                    _formatTime(message.timestamp),
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channelName),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadMessages,
            tooltip: 'Refresh messages',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoadingMessages)
            LinearProgressIndicator(),
          
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Text(
                      'No messages yet\nStart the conversation!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    reverse: true,
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final message = _messages[_messages.length - 1 - index];
                      return _buildMessageBubble(message);
                    },
                  ),
          ),
          
          Padding(
            padding: EdgeInsets.all(8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 16),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                
                SizedBox(width: 8),
                
                AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  child: IconButton(
                    icon: Icon(
                      _isRecording ? Icons.stop : Icons.mic,
                      color: _isRecording ? Colors.red : Colors.blue,
                    ),
                    onPressed: _toggleVoiceRecording,
                    tooltip: _isRecording ? 'Stop recording' : 'Record voice message',
                  ),
                ),
                
                SizedBox(width: 8),
                
                AnimatedContainer(
                  duration: Duration(milliseconds: 300),
                  child: _isLoading
                      ? CircularProgressIndicator()
                      : IconButton(
                          icon: Icon(Icons.send, color: Colors.blue),
                          onPressed: _sendMessage,
                          tooltip: 'Send message',
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
