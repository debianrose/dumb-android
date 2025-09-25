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
  final _scrollController = ScrollController();
  
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

  Future<void> _sendMessage() async {
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

  @override
  void dispose() {
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
                          final isMe = message.from == widget.currentUser;
                          
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
                                        Text(message.text),
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
                        },
                      ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _messageController,
                    decoration: const InputDecoration(
                      hintText: 'Type a message...',
                      border: OutlineInputBorder(),
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
}
