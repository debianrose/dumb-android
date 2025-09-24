import 'package:flutter/material.dart';
import 'api_client.dart';
import 'websocket_client.dart';
import 'models.dart';
import 'utils.dart';

class ChatScreen extends StatefulWidget {
  final ApiClient apiClient;
  final String currentUser;
  final VoidCallback onLogout;

  const ChatScreen({
    super.key,
    required this.apiClient,
    required this.currentUser,
    required this.onLogout,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final WebSocketClient _wsClient = WebSocketClient();
  final _messageController = TextEditingController();
  final _channelJoinController = TextEditingController();
  
  List<Channel> _channels = [];
  List<Message> _messages = [];
  List<User> _users = [];
  Channel? _selectedChannel;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _initializeChat();
  }

  Future<void> _initializeChat() async {
    await _loadChannels();
    await _loadUsers();
    
    final token = await getStoredToken();
    if (token != null) {
      _wsClient.connect(token);
      _wsClient.messageStream.listen(_handleNewMessage);
    }
    
    setState(() => _isLoading = false);
  }

  Future<void> _loadChannels() async {
    final response = await widget.apiClient.getChannels();
    if (response.success) {
      setState(() {
        _channels = (response.data?['channels'] as List?)
            ?.map((json) => Channel.fromJson(json))
            .toList() ?? [];
        if (_channels.isNotEmpty && _selectedChannel == null) {
          _selectedChannel = _channels.first;
          _loadMessages();
        }
      });
    }
  }

  Future<void> _loadMessages() async {
    if (_selectedChannel == null) return;
    
    final response = await widget.apiClient.getMessages(_selectedChannel!.id);
    if (response.success) {
      setState(() {
        _messages = (response.data?['messages'] as List?)
            ?.map((json) => Message.fromJson(json))
            .toList() ?? [];
      });
    }
  }

  Future<void> _loadUsers() async {
    final response = await widget.apiClient.getUsers();
    if (response.success) {
      setState(() {
        _users = (response.data?['users'] as List?)
            ?.map((json) => User.fromJson(json))
            .toList() ?? [];
      });
    }
  }

  void _handleNewMessage(Message message) {
    if (message.channel == _selectedChannel?.id) {
      setState(() {
        _messages.insert(0, message);
      });
    }
  }

  Future<void> _sendMessage() async {
    if (_messageController.text.isEmpty || _selectedChannel == null) return;
    
    final response = await widget.apiClient.sendMessage(
      _selectedChannel!.id,
      _messageController.text,
    );
    
    if (response.success) {
      _messageController.clear();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: ${response.error}')),
      );
    }
  }

  Future<void> _joinChannel(String channelId) async {
    final response = await widget.apiClient.joinChannel(channelId);
    if (response.success) {
      await _loadChannels();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Канал присоединен')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: ${response.error}')),
      );
    }
  }

  void _show2FAManagement() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Управление 2FA'),
        content: FutureBuilder<ApiResponse>(
          future: widget.apiClient.get2FAStatus(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            
            final enabled = snapshot.data?.data?['enabled'] == true;
            
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('2FA: ${enabled ? 'Включена' : 'Выключена'}'),
                const SizedBox(height: 20),
                if (!enabled)
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _setup2FA();
                    },
                    child: const Text('Включить 2FA'),
                  )
                else
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context);
                      _disable2FA();
                    },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                    child: const Text('Выключить 2FA'),
                  ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Закрыть'),
          ),
        ],
      ),
    );
  }

  void _setup2FA() {
    // Логика настройки 2FA будет в AuthScreen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Настройка 2FA доступна на экране входа')),
    );
  }

  void _disable2FA() {
    final passwordController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выключение 2FA'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Для выключения 2FA введите ваш пароль:'),
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Пароль',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () async {
              final response = await widget.apiClient.disable2FA(passwordController.text);
              if (response.success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('2FA выключена')),
                );
                Navigator.pop(context);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Ошибка: ${response.error}')),
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Выключить'),
          ),
        ],
      ),
    );
  }

  void _showChannelDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Присоединиться к каналу'),
        content: TextField(
          controller: _channelJoinController,
          decoration: const InputDecoration(hintText: 'ID канала'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              final channelId = _channelJoinController.text.trim();
              if (channelId.isNotEmpty) {
                _joinChannel(channelId);
                Navigator.pop(context);
                _channelJoinController.clear();
              }
            },
            child: const Text('Присоединиться'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_selectedChannel?.name ?? 'Чат'),
        actions: [
          PopupMenuButton(
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'join_channel',
                child: Row(
                  children: [
                    Icon(Icons.add),
                    SizedBox(width: 8),
                    Text('Присоединиться к каналу'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: '2fa_management',
                child: Row(
                  children: [
                    Icon(Icons.security),
                    SizedBox(width: 8),
                    Text('Управление 2FA'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Выйти'),
                  ],
                ),
              ),
            ],
            onSelected: (value) {
              switch (value) {
                case 'join_channel':
                  _showChannelDialog();
                  break;
                case '2fa_management':
                  _show2FAManagement();
                  break;
                case 'logout':
                  widget.onLogout();
                  break;
              }
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Row(
              children: [
                // Список каналов
                Container(
                  width: 200,
                  decoration: const BoxDecoration(
                    border: Border(right: BorderSide(color: Colors.grey)),
                  ),
                  child: ListView.builder(
                    itemCount: _channels.length,
                    itemBuilder: (context, index) {
                      final channel = _channels[index];
                      return ListTile(
                        title: Text(channel.name),
                        subtitle: Text('${channel.memberCount} участников'),
                        selected: _selectedChannel?.id == channel.id,
                        onTap: () {
                          setState(() {
                            _selectedChannel = channel;
                          });
                          _loadMessages();
                        },
                      );
                    },
                  ),
                ),
                // Чат
                Expanded(
                  child: Column(
                    children: [
                      // Сообщения
                      Expanded(
                        child: _selectedChannel == null
                            ? const Center(child: Text('Выберите канал'))
                            : ListView.builder(
                                reverse: true,
                                itemCount: _messages.length,
                                itemBuilder: (context, index) {
                                  final message = _messages[index];
                                  final isMe = message.from == widget.currentUser;
                                  
                                  return ListTile(
                                    title: Row(
                                      mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isMe ? Colors.blue.shade100 : Colors.grey.shade100,
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                isMe ? 'Вы' : message.from,
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: isMe ? Colors.blue.shade800 : Colors.grey.shade800,
                                                ),
                                              ),
                                              if (message.text.isNotEmpty) Text(message.text),
                                              if (message.file != null)
                                                Text('📎 ${message.file!.originalName}'),
                                              if (message.voice != null)
                                                Text('🎤 ${message.voice!.duration}сек'),
                                              Text(
                                                formatTime(message.ts),
                                                style: const TextStyle(fontSize: 12, color: Colors.grey),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                      // Поле ввода
                      if (_selectedChannel != null)
                        Container(
                          padding: const EdgeInsets.all(8),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: _messageController,
                                  decoration: const InputDecoration(
                                    hintText: 'Введите сообщение...',
                                    border: OutlineInputBorder(),
                                  ),
                                  onSubmitted: (_) => _sendMessage(),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.send),
                                onPressed: _sendMessage,
                              ),
                            ],
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
