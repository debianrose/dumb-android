import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'auth_screen.dart';
import 'channel_select_screen.dart';
import 'chat_screen.dart';
import 'server_config_screen.dart';
import 'api_client.dart';
import 'utils.dart';
import 'l10n/app_localizations.dart';

class ChatApp extends StatefulWidget {
  const ChatApp({super.key});

  @override
  State<ChatApp> createState() => _ChatAppState();
}

class _ChatAppState extends State<ChatApp> {
  final ApiClient _apiClient = ApiClient();
  String? _currentUser;
  bool _showServerConfig = false;
  String? _selectedChannelId;
  bool _isInitializing = true;

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    try {
      await _apiClient.loadServerConfig();
      
      final token = await getStoredToken();
      if (token != null) {
        _apiClient.setToken(token);
        
        final user = await _apiClient.validateToken(token);
        if (user != null) {
          setState(() {
            _currentUser = user;
          });
        } else {
          await clearStoredToken();
        }
      }
    } catch (e) {
      print('Initialization error: $e');
    } finally {
      setState(() {
        _isInitializing = false;
      });
    }
  }

  void _onLogin(String user, String token) {
    setState(() {
      _currentUser = user;
    });
  }

  void _onLogout() {
    setState(() {
      _currentUser = null;
      _selectedChannelId = null;
    });
    _apiClient.logout();
  }

  void _showServerConfigScreen() {
    setState(() {
      _showServerConfig = true;
    });
  }

  void _hideServerConfigScreen() {
    setState(() {
      _showServerConfig = false;
    });
    _initializeApp();
  }

  void _onChannelSelected(String channelId) {
    setState(() {
      _selectedChannelId = channelId;
    });
  }

  void _onBackFromChat() {
    setState(() {
      _selectedChannelId = null;
    });
  }

  Widget _buildLocalizedApp(Widget home) {
    return MaterialApp(
      home: home,
      debugShowCheckedModeBanner: false,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isInitializing) {
      return _buildLocalizedApp(
        Scaffold(
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 20),
                Text('Loading...'),
              ],
            ),
          ),
        ),
      );
    }

    if (_showServerConfig) {
      return _buildLocalizedApp(
        ServerConfigScreen(
          apiClient: _apiClient,
          onConfigSaved: _hideServerConfigScreen,
        ),
      );
    }

    if (_currentUser == null) {
      return _buildLocalizedApp(
        AuthScreen(
          apiClient: _apiClient,
          onLogin: _onLogin,
          onConfigPressed: _showServerConfigScreen,
        ),
      );
    }

    if (_selectedChannelId != null) {
      return _buildLocalizedApp(
        ChatScreen(
          apiClient: _apiClient,
          currentUser: _currentUser!,
          channelId: _selectedChannelId!,
          onBack: _onBackFromChat,
        ),
      );
    }

    return _buildLocalizedApp(
      ChannelSelectScreen(
        apiClient: _apiClient,
        currentUser: _currentUser!,
        onLogout: _onLogout,
        onConfigPressed: _showServerConfigScreen,
        onChannelSelected: _onChannelSelected,
      ),
    );
  }
}
