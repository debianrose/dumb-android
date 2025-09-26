import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:math';
import 'dart:async';
import 'api_client.dart';
import 'websocket_client.dart';
import 'models.dart';
import 'utils.dart';
import 'voice_recorder_widget.dart';
import 'audio_level_visualizer.dart';
import 'audio_service.dart';

class ChatScreen extends StatefulWidget {
  final ApiClient apiClient;
  final String currentUser;
  final String channelId;
  final VoidCallback onBack;

  const ChatScreen({
    super.key,
    required this.apiClient,
    required this.currentUser,
    required this.channelId,
    required this.onBack,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with TickerProviderStateMixin {
  late WebSocketClient _wsClient;
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final MyAudioService _audioService = MyAudioService();
  
  List<Message> _messages = [];
  Channel? _channel;
  bool _isLoading = true;
  String? _currentPlayingMessageId;

  @override
  void initState() {
    super.initState();
    _wsClient = WebSocketClient();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    await _loadChannelInfo();
    await _loadMessages();
    
    final token = await getStoredToken();
    if (token != null) {
      await _wsClient.connect(token);
      _wsClient.messageStream.listen(_handleNewMessage);
    }
    
    setState(() => _isLoading = false);
    _scrollToBottom();
  }

  Future<void> _loadChannelInfo() async {
    try {
      final response = await widget.apiClient.getChannels();
      if (response.success) {
        final channels = (response.data?['channels'] as List?)
            ?.map((json) => Channel.fromJson(json))
            .toList() ?? [];
        
        final channel = channels.firstWhere(
          (channel) => channel.id == widget.channelId,
          orElse: () => Channel(
            id: widget.channelId,
            name: 'Unknown Channel',
            createdBy: 'Unknown',
            createdAt: 0,
            memberCount: 0,
          ),
        );
        
        setState(() => _channel = channel);
      }
    } catch (e) {
      print('Error loading channel info: $e');
    }
  }

  Future<void> _loadMessages() async {
    try {
      final response = await widget.apiClient.getMessages(widget.channelId);
      if (response.success) {
        setState(() {
          _messages = (response.data?['messages'] as List?)
              ?.map((json) => Message.fromJson(json))
              .toList() ?? [];
        });
        _scrollToBottom();
      }
    } catch (e) {
      print('Error loading messages: $e');
    }
  }

  void _handleNewMessage(Message message) {
    if (message.channel == widget.channelId) {
      setState(() {
        _messages.insert(0, message);
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendTextMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    
    try {
      final response = await widget.apiClient.sendMessage(widget.channelId, text);
      
      if (response.success) {
        _messageController.clear();
      } else {
        _showError('Error: ${response.error}');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  void _startVoiceRecording() {
    showModalBottomSheet(
      context: context,
      builder: (context) => VoiceRecorderWidget(
        onRecordingComplete: (filePath) {
          Navigator.pop(context);
          _sendVoiceMessage(filePath);
        },
        onCancel: () {
          Navigator.pop(context);
        },
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _sendVoiceMessage(String filePath) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final uploadResponse = await widget.apiClient.uploadVoiceMessage(
        widget.channelId, 
        filePath
      );

      if (uploadResponse.success && uploadResponse.data?['voiceId'] != null) {
        final voiceId = uploadResponse.data?['voiceId'];
        final sendResponse = await widget.apiClient.sendVoiceOnlyMessage(
          widget.channelId, 
          voiceId
        );

        if (!sendResponse.success) {
          _showError('Ошибка отправки: ${sendResponse.error}');
        }
      } else {
        _showError('Ошибка загрузки: ${uploadResponse.error}');
      }
    } catch (e) {
      _showError('Ошибка: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _playVoiceMessage(Message message) async {
    if (_currentPlayingMessageId == message.id) {
      await _audioService.stopPlaying();
      setState(() {
        _currentPlayingMessageId = null;
      });
      return;
    }

    try {
      setState(() {
        _currentPlayingMessageId = message.id;
      });

      final downloadUrl = '${widget.apiClient.getCurrentUrl()}/api/download/${message.voice!.filename}';
      await _audioService.playRecording(downloadUrl);
      
      _audioService.playbackCompleteStream.listen((_) {
        if (mounted) {
          setState(() {
            _currentPlayingMessageId = null;
          });
        }
      });
    } catch (e) {
      _showError('Ошибка воспроизведения: $e');
      setState(() {
        _currentPlayingMessageId = null;
      });
    }
  }

  void _leaveChannel() async {
    try {
      final response = await widget.apiClient.leaveChannel(widget.channelId);
      if (response.success) {
        _showSuccess('Success');
        widget.onBack();
      } else {
        _showError('Error: ${response.error}');
      }
    } catch (e) {
      _showError('Error: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inMinutes < 1) return 'now';
    if (difference.inHours < 1) return '${difference.inMinutes}m';
    if (difference.inDays < 1) return '${difference.inHours}h';
    
    return '${date.day}.${date.month}.${date.year}';
  }

  Widget _buildVoiceMessageWidget(Message message, bool isPlaying) {
    final duration = message.voice?.duration ?? 0;
    final isMe = message.from == widget.currentUser;
    
    return GestureDetector(
      onTap: () => _playVoiceMessage(message),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isMe 
              ? (isPlaying ? Colors.blue.shade200 : Colors.blue.shade100)
              : (isPlaying ? Colors.grey.shade200 : Colors.grey.shade100),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
            color: isPlaying 
                ? (isMe ? Colors.blue.shade300 : Colors.grey.shade300)
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: isMe ? Colors.blue : Colors.grey.shade600,
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause : Icons.play_arrow,
                color: Colors.white,
                size: 16,
              ),
            ),
            
            const SizedBox(width: 12),
            
            if (isPlaying)
              AudioLevelVisualizer(
                audioLevels: [0.3, 0.5, 0.7, 0.9, 0.7, 0.5, 0.3],
                barCount: 7,
                maxHeight: 20,
                baseColor: isMe ? Colors.blue : Colors.grey.shade600,
                isActive: true,
              )
            else
              Container(
                width: 60,
                height: 20,
                child: Center(
                  child: Text(
                    '${(duration / 60).floor()}:${(duration % 60).toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: isMe ? Colors.blue.shade800 : Colors.grey.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            
            const SizedBox(width: 8),
            
            Icon(
              Icons.mic,
              color: isMe ? Colors.blue.shade600 : Colors.grey.shade600,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileAttachment(FileAttachment file) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.insert_drive_file, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.originalName,
                  style: TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${(file.size / 1024).toStringAsFixed(1)} KB',
                  style: TextStyle(fontSize: 10, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage(Message message) {
    final isMe = message.from == widget.currentUser;
    final isPlaying = _currentPlayingMessageId == message.id;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isMe ? Colors.blue.shade100 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Text(
                      message.from,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  
                  if (message.isVoiceMessage)
                    _buildVoiceMessageWidget(message, isPlaying)
                  else
                    Text(message.text),
                  
                  if (message.hasFile && !message.isVoiceMessage)
                    _buildFileAttachment(message.file!),
                  
                  const SizedBox(height: 4),
                  Text(
                    _formatTimestamp(message.ts),
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
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

  Widget _buildMessageInput() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          IconButton(
            icon: Icon(Icons.mic, color: Colors.blue),
            onPressed: _startVoiceRecording,
            tooltip: 'Запись голосового сообщения',
          ),
          
          Expanded(
            child: TextField(
              controller: _messageController,
              decoration: const InputDecoration(
                hintText: 'Type a message...',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _sendTextMessage(),
            ),
          ),
          
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.send),
            onPressed: _sendTextMessage,
            style: IconButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _audioService.dispose();
    _wsClient.disconnect();
    _scrollController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_channel?.name ?? 'Loading...'),
            if (_channel != null)
              Text(
                '${_channel!.memberCount} members',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        actions: [
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 12),
                    Text('Refresh'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app),
                    SizedBox(width: 12),
                    Text('Leave Channel'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'refresh':
                  _loadMessages();
                  _loadChannelInfo();
                  break;
                case 'leave':
                  _leaveChannel();
                  break;
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading)
            const LinearProgressIndicator()
          else
            const SizedBox(height: 1),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey),
                            const SizedBox(height: 16),
                            const Text(
                              'No messages',
                              style: TextStyle(fontSize: 18),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Be the first to message in this channel!',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        reverse: true,
                        controller: _scrollController,
                        padding: const EdgeInsets.all(16),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) {
                          final message = _messages[index];
                          return _buildMessage(message);
                        },
                      ),
          ),
          _buildMessageInput(),
        ],
      ),
    );
  }
}
