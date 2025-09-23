import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:permission_handler/permission_handler.dart';

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
  bool _isRecording = false;
  bool _isLoading = false;
  String? _currentPlayingMessageId;
  int _currentPosition = 0;
  int _voiceDuration = 0;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _startMessageRefresh();
  }

  @override
  void dispose() {
    _audioPlayer.dispose();
    super.dispose();
  }

  Future<void> _loadMessages() async {
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
      }
    } catch (e) {
      print('Error loading messages: $e');
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
      } else {
        _showError(result['error'] ?? 'Failed to send message');
      }
    } catch (e) {
      _showError('Failed to send message');
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

    setState(() {
      _isRecording = true;
    });
    _showSuccess('Recording started');
  }

  Future<void> _stopRecording() async {
    setState(() {
      _isRecording = false;
    });
    _showSuccess('Recording stopped');
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
        setState(() {
          _currentPosition = duration.inMilliseconds;
        });
      });

      _audioPlayer.onPlayerComplete.listen((_) {
        _stopVoicePlayback();
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
    setState(() {
      _currentPlayingMessageId = null;
      _currentPosition = 0;
    });
  }

  int _getVoiceProgress(String messageId) {
    if (_currentPlayingMessageId == messageId && _voiceDuration > 0) {
      return (_currentPosition * 100 ~/ _voiceDuration);
    }
    return 0;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  String _formatTime(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatDuration(int seconds) {
    if (seconds <= 0) return '0:00';
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.channelName),
        actions: [
          IconButton(
            icon: Icon(Icons.call),
            onPressed: () {
              _showError('Voice calls not implemented yet');
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              reverse: true,
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                final message = _messages[_messages.length - 1 - index];
                final isPlaying = _currentPlayingMessageId == message.id;
                final progress = _getVoiceProgress(message.id);

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: Text(
                      message.from,
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (message.text.isNotEmpty) Text(message.text),
                        if (message.voice != null) ...[
                          SizedBox(height: 8),
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(isPlaying ? Icons.pause : Icons.mic),
                                onPressed: () => _toggleVoiceMessage(message),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    LinearProgressIndicator(
                                      value: progress / 100.0,
                                    ),
                                    SizedBox(height: 4),
                                    Text(_formatDuration(message.voice!.duration)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    trailing: Text(_formatTime(message.timestamp)),
                  ),
                );
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
                    ),
                  ),
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                  onPressed: _toggleVoiceRecording,
                  color: _isRecording ? Colors.red : null,
                ),
                SizedBox(width: 8),
                IconButton(
                  icon: _isLoading ? CircularProgressIndicator() : Icon(Icons.send),
                  onPressed: _isLoading ? null : _sendMessage,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
