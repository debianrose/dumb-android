import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'chat_screen.dart';
import 'two_fa_management_screen.dart';

class Channel {
  final String id;
  final String name;
  final String owner;

  Channel({required this.id, required this.name, required this.owner});
}

class ChannelSelectionScreen extends StatefulWidget {
  final String token;
  final String username;

  ChannelSelectionScreen({required this.token, required this.username});

  @override
  _ChannelSelectionScreenState createState() => _ChannelSelectionScreenState();
}

class _ChannelSelectionScreenState extends State<ChannelSelectionScreen> {
  final TextEditingController _channelController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  List<Channel> _allChannels = [];
  List<Channel> _filteredChannels = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadAllChannels();
    _searchController.addListener(_filterChannels);
  }

  Future<void> _loadAllChannels() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/channels/search'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({'query': '%'}),
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        setState(() {
          _allChannels.clear();
          _filteredChannels.clear();
          
          final channelsArray = result['channels'] as List?;
          if (channelsArray != null) {
            for (var channelObj in channelsArray) {
              final channel = Channel(
                id: channelObj['id'] ?? '',
                name: channelObj['name'] ?? '',
                owner: channelObj['creator'] ?? '',
              );
              _allChannels.add(channel);
              _filteredChannels.add(channel);
            }
          }
        });
        
        _showSuccess('Loaded ${_allChannels.length} channels');
      } else {
        _showError('Failed to load channels');
      }
    } catch (e) {
      _showError('Failed to load channels');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _filterChannels() {
    final query = _searchController.text.toLowerCase();
    
    setState(() {
      if (query.isEmpty) {
        _filteredChannels = List.from(_allChannels);
      } else {
        _filteredChannels = _allChannels.where((channel) {
          return channel.name.toLowerCase().contains(query) ||
                 channel.id.toLowerCase().contains(query);
        }).toList();
      }
    });
  }

  Future<void> _joinChannel(Channel channel) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/channels/join'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({'channel': channel.id}),
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        _openChat(channel);
      } else {
        _showError(result['error'] ?? 'Failed to join channel');
      }
    } catch (e) {
      _showError('Failed to join channel');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _createChannel() async {
    final channelName = _channelController.text.trim();
    
    if (channelName.isEmpty) {
      _showError('Please enter channel name');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/channels/create'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({'name': channelName}),
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        final channelId = result['channelId'];
        if (channelId != null) {
          await _joinChannelById(channelId);
        } else {
          await _loadAllChannels();
        }
        _channelController.clear();
        _showSuccess('Channel created: $channelName');
      } else {
        _showError(result['error'] ?? 'Failed to create channel');
      }
    } catch (e) {
      _showError('Failed to create channel');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _joinChannelById(String channelId) async {
    try {
      final response = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/channels/join'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({'channel': channelId}),
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        await _loadAllChannels();
      } else {
        _showError(result['error'] ?? 'Failed to join channel');
      }
    } catch (e) {
      _showError('Failed to join channel');
    }
  }

  void _openChat(Channel channel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          token: widget.token,
          username: widget.username,
          channelId: channel.id,
          channelName: channel.name,
        ),
      ),
    );
  }

  void _open2FAManagement() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TwoFAManagementScreen(
          token: widget.token,
          username: widget.username,
        ),
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Channels'),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh),
            onPressed: _loadAllChannels,
          ),
          IconButton(
            icon: Icon(Icons.security),
            onPressed: _open2FAManagement,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    labelText: 'Search channels',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _channelController,
                        decoration: InputDecoration(
                          labelText: 'Channel name/ID',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(width: 12),
                    ElevatedButton(
                      onPressed: _createChannel,
                      child: Text('Create'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _filteredChannels.length,
                    itemBuilder: (context, index) {
                      final channel = _filteredChannels[index];
                      return ListTile(
                        title: Text(channel.name),
                        subtitle: Text('ID: ${channel.id} • Owner: ${channel.owner}'),
                        onTap: () => _joinChannel(channel),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
