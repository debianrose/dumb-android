import 'package:flutter/material.dart';
import 'api_client.dart';
import 'models.dart';
import 'l10n/app_localizations.dart';

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
      
      if (response.success) {
        final channelsData = response.data?['channels'] as List?;
        if (channelsData != null) {
          final List<Channel> loadedChannels = [];
          
          for (var item in channelsData) {
            try {
              if (item is Map<String, dynamic>) {
                loadedChannels.add(Channel.fromJson(item));
              }
            } catch (e) {
              print('Error parsing channel: $e');
            }
          }
          
          setState(() {
            _channels = loadedChannels;
            _isLoading = false;
          });
        } else {
          setState(() {
            _channels = [];
            _isLoading = false;
          });
        }
      } else {
        setState(() {
          _errorMessage = response.error ?? AppLocalizations.of(context).connectionError;
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = '${AppLocalizations.of(context).error}: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _createChannel() async {
    final channelName = _channelNameController.text.trim();
    
    if (channelName.isEmpty) {
      _showError(AppLocalizations.of(context).channelName);
      return;
    }

    setState(() => _isCreatingChannel = true);

    try {
      final response = await widget.apiClient.createChannel(channelName);
      
      setState(() => _isCreatingChannel = false);

      if (response.success) {
        _showSuccess('${AppLocalizations.of(context).success}!');
        _channelNameController.clear();
        await Future.delayed(const Duration(milliseconds: 500));
        await _loadChannels();
        if (mounted) Navigator.of(context).pop();
      } else {
        _showError('${AppLocalizations.of(context).error}: ${response.error}');
      }
    } catch (e) {
      setState(() => _isCreatingChannel = false);
      _showError('${AppLocalizations.of(context).error}: $e');
    }
  }

  Future<void> _joinChannelByName() async {
    final channelName = _joinChannelController.text.trim();
    
    if (channelName.isEmpty) {
      _showError(AppLocalizations.of(context).channelName);
      return;
    }

    setState(() => _isJoiningChannel = true);

    try {
      final response = await widget.apiClient.joinChannel(channelName);
      
      setState(() => _isJoiningChannel = false);

      if (response.success) {
        _showSuccess('${AppLocalizations.of(context).success}!');
        _joinChannelController.clear();
        if (mounted) {
          Navigator.of(context).pop();
          await _loadChannels();
        }
      } else {
        _showError('${AppLocalizations.of(context).error}: ${response.error}');
      }
    } catch (e) {
      setState(() => _isJoiningChannel = false);
      _showError('${AppLocalizations.of(context).error}: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Theme.of(context).colorScheme.error,
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

  void _showCreateChannelDialog() {
    final loc = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.createChannel),
        content: TextField(
          controller: _channelNameController,
          decoration: InputDecoration(
            labelText: loc.channelName,
          ),
          onSubmitted: (_) => _createChannel(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: _isCreatingChannel ? null : _createChannel,
            child: _isCreatingChannel 
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(loc.createChannel),
          ),
        ],
      ),
    );
  }

  void _showJoinChannelDialog() {
    final loc = AppLocalizations.of(context);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(loc.joinChannel),
        content: TextField(
          controller: _joinChannelController,
          decoration: InputDecoration(
            labelText: loc.channelName,
          ),
          onSubmitted: (_) => _joinChannelByName(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(loc.cancel),
          ),
          FilledButton(
            onPressed: _isJoiningChannel ? null : _joinChannelByName,
            child: _isJoiningChannel
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(loc.joinChannel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.channels),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: widget.onConfigPressed,
            tooltip: loc.settings,
          ),
          PopupMenuButton(
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'refresh',
                child: Row(
                  children: [
                    const Icon(Icons.refresh),
                    const SizedBox(width: 12),
                    Text(loc.refresh),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    const Icon(Icons.logout),
                    const SizedBox(width: 12),
                    Text(loc.logout),
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
          const SizedBox(height: 12),
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
                      Icon(Icons.error_outline, size: 64, color: colorScheme.error),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _loadChannels,
                        child: Text(loc.retry),
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
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.chat_bubble_outline, size: 64, color: colorScheme.outline),
                                  const SizedBox(height: 16),
                                  Text(
                                    loc.noChannelsAvailable,
                                    style: theme.textTheme.headlineSmall,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '${loc.createChannel} ${loc.joinChannel.toLowerCase()}',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: colorScheme.outline,
                                    ),
                                    textAlign: TextAlign.center,
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
                              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                              child: ListTile(
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(Icons.chat, color: colorScheme.onPrimaryContainer),
                                ),
                                title: Text(channel.name),
                                subtitle: Text(
                                  '${loc.createdBy}: ${channel.createdBy}\n'
                                  '${channel.memberCount} ${loc.members}',
                                ),
                                trailing: const Icon(Icons.arrow_forward_ios),
                                onTap: () => widget.onChannelSelected(channel.id),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
