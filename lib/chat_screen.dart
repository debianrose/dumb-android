import 'package:flutter/material.dart';
import 'api_client.dart';
import 'websocket_client.dart';
import 'models.dart';
import 'utils.dart';

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

class _ChatScreenState extends State<ChatScreen> {
  late WebSocketClient _wsClient;
  final _messageController = TextEditingController();
  
  List<Message> _messages = [];
  Channel? _channel;
  bool _isLoading = true;

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
            name: 'Неизвестный канал',
            createdBy: 'Неизвестно',
            createdAt: 0,
            memberCount: 0,
          ),
        );
        
        setState(() {
          _channel = channel;
        });
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
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty) return;
    
    try {
      final response = await widget.apiClient.sendMessage(
        widget.channelId,
        _messageController.text,
      );
      
      if (response.success) {
        _messageController.clear();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${response.error}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки: $e')),
      );
    }
  }

  void _leaveChannel() async {
    try {
      final response = await widget.apiClient.leaveChannel(widget.channelId);
      if (response.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Покинули канал')),
        );
        widget.onBack();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: ${response.error}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack,
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_channel?.name ?? 'Загрузка...'),
            if (_channel != null)
              Text(
                'Участников: ${_channel!.memberCount}',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        actions: [
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'leave',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app),
                    SizedBox(width: 8),
                    Text('Покинуть канал'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    Icon(Icons.refresh),
                    SizedBox(width: 8),
                    Text('Обновить'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'leave':
                  _leaveChannel();
                  break;
                case 'refresh':
                  _loadMessages();
                  _loadChannelInfo();
                  break;
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Expanded(
                  child: _messages.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.chat, size: 64, color: Colors.grey),
                              SizedBox(height: 16),
                              Text(
                                'Нет сообщений',
                                style: TextStyle(fontSize: 18, color: Colors.grey),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Будьте первым, кто напишет в этом канале!',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          reverse: true,
                          itemCount: _messages.length,
                          itemBuilder: (context, index) {
                            final message = _messages[index];
                            final isMe = message.from == widget.currentUser;
                            
                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 8),
                              child: Row(
                                mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                children: [
                                  Flexible(
                                    child: Container(
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
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Colors.blue.shade800,
                                              ),
                                            ),
                                          if (message.text.isNotEmpty) 
                                            Text(message.text),
                                          if (message.file != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.attach_file, size: 16),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    message.file!.originalName,
                                                    style: const TextStyle(fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          if (message.voice != null)
                                            Padding(
                                              padding: const EdgeInsets.only(top: 4),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.mic, size: 16),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    '${message.voice!.duration}сек',
                                                    style: const TextStyle(fontSize: 12),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          const SizedBox(height: 4),
                                          Text(
                                            formatTime(message.ts),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _messageController,
                          decoration: const InputDecoration(
                            hintText: 'Введите сообщение...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12),
                          ),
                          onSubmitted: (_) => _sendMessage(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  @override
  void dispose() {
    _wsClient.disconnect();
    super.dispose();
  }
}
