import 'package:flutter/material.dart';
import 'api_client.dart';
import 'models.dart';

class ChannelSelectScreen extends StatefulWidget {
  final ApiClient apiClient;
  final String currentUser;
  final VoidCallback onLogout;
  final VoidCallback onConfigPressed;
  final Function(String) onChannelSelected;

  const ChannelSelectScreen({
    super.key,
    required this.apiClient,
    required this.currentUser,
    required this.onLogout,
    required this.onConfigPressed,
    required this.onChannelSelected,
  });

  @override
  State<ChannelSelectScreen> createState() => _ChannelSelectScreenState();
}

class _ChannelSelectScreenState extends State<ChannelSelectScreen> {
  final _channelNameController = TextEditingController();
  final _joinChannelController = TextEditingController();
  List<Channel> _channels = [];
  bool _isLoading = true;
  bool _isCreatingChannel = false;
  bool _isJoiningChannel = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadChannels();
  }

  Future<void> _loadChannels() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await widget.apiClient.getChannels();
      
      print('Channels response: ${response.success}');
      print('Channels data: ${response.data}');
      
      if (response.success) {
        final channelsData = response.data?['channels'] as List?;
        if (channelsData != null) {
          final List<Channel> loadedChannels = [];
          
          for (var item in channelsData) {
            try {
              if (item is Map<String, dynamic>) {
                print('Channel data: $item');
                loadedChannels.add(Channel.fromJson(item));
              }
            } catch (e) {
              print('Error parsing channel: $e, data: $item');
            }
          }
          
          setState(() {
            _channels = loadedChannels;
            _isLoading = false;
          });
          
          print('Loaded ${_channels.length} channels');
        } else {
          setState(() {
            _channels = [];
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = response.error ?? 'Ошибка загрузки каналов';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Ошибка соединения: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _createChannel() async {
    final channelName = _channelNameController.text.trim();
    
    if (channelName.isEmpty) {
      _showError('Введите название канала');
      return;
    }

    setState(() {
      _isCreatingChannel = true;
    });

    try {
      final response = await widget.apiClient.createChannel(channelName);
      
      setState(() {
        _isCreatingChannel = false;
      });

      if (response.success) {
        _showSuccess('Канал "$channelName" создан!');
        _channelNameController.clear();
        
        // Ждем немного перед обновлением списка
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Перезагружаем каналы
        await _loadChannels();
        
        // Закрываем диалог только после успешной загрузки
        if (mounted) {
          Navigator.of(context).pop();
        }
      } else {
        _showError('Ошибка создания канала: ${response.error}');
      }
    } catch (e) {
      setState(() {
        _isCreatingChannel = false;
      });
      _showError('Ошибка: $e');
    }
  }

  Future<void> _joinChannelByName() async {
    final channelName = _joinChannelController.text.trim();
    
    if (channelName.isEmpty) {
      _showError('Введите название канала');
      return;
    }

    setState(() {
      _isJoiningChannel = true;
    });

    try {
      final response = await widget.apiClient.joinChannel(channelName);
      
      setState(() {
        _isJoiningChannel = false;
      });

      if (response.success) {
        _showSuccess('Присоединились к каналу "$channelName"!');
        _joinChannelController.clear();
        if (mounted) {
          Navigator.of(context).pop();
          await _loadChannels();
        }
      } else {
        _showError('Ошибка присоединения: ${response.error}');
      }
    } catch (e) {
      setState(() {
        _isJoiningChannel = false;
      });
      _showError('Ошибка: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showCreateChannelDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Создать канал'),
            content: TextField(
              controller: _channelNameController,
              decoration: const InputDecoration(
                hintText: 'Название канала',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _createChannel(),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: _isCreatingChannel ? null : _createChannel,
                child: _isCreatingChannel 
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Создать'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showJoinChannelDialog() {
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Присоединиться к каналу'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _joinChannelController,
                  decoration: const InputDecoration(
                    hintText: 'Название или ID канала',
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => _joinChannelByName(),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Отмена'),
              ),
              ElevatedButton(
                onPressed: _isJoiningChannel ? null : _joinChannelByName,
                child: _isJoiningChannel
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Присоединиться'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Каналы'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: widget.onConfigPressed,
              tooltip: 'Настройки сервера',
            ),
            PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'refresh',
                  child: Row(
                    children: [
                      Icon(Icons.refresh),
                      SizedBox(width: 8),
                      Text('Обновить список'),
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
                  case 'refresh':
                    _loadChannels();
                    break;
                  case 'logout':
                    widget.onLogout();
                    break;
                }
              },
            ),
          ],
        ),
        floatingActionButton: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            FloatingActionButton(
              heroTag: 'join_fab',
              onPressed: _showJoinChannelDialog,
              mini: true,
              child: const Icon(Icons.group_add),
            ),
            const SizedBox(height: 10),
            FloatingActionButton(
              heroTag: 'create_fab',
              onPressed: _showCreateChannelDialog,
              child: const Icon(Icons.add),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error, size: 64, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(fontSize: 16, color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton(
                          onPressed: _loadChannels,
                          child: const Text('Повторить'),
                        ),
                      ],
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _loadChannels,
                    child: _channels.isEmpty
                        ? SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: MediaQuery.of(context).size.height * 0.8,
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.group, size: 64, color: Colors.grey),
                                    SizedBox(height: 16),
                                    Text(
                                      'Нет доступных каналов',
                                      style: TextStyle(fontSize: 18, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: _channels.length,
                            itemBuilder: (context, index) {
                              final channel = _channels[index];
                              return Card(
                                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                child: ListTile(
                                  leading: const Icon(Icons.chat),
                                  title: Text(channel.name),
                                  subtitle: Text(
                                    'Создал: ${channel.createdBy}\n'
                                    'Участников: ${channel.memberCount}',
                                  ),
                                  trailing: const Icon(Icons.arrow_forward_ios),
                                  onTap: () => widget.onChannelSelected(channel.id),
                                ),
                              );
                            },
                          ),
                  ),
      ),
    );
  }
}
