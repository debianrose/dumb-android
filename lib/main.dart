import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mime/mime.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:record/record.dart';
import 'package:dumb_android/l10n/app_localizations.dart';

String apiUrl = 'http://localhost:3000/api';
String? _cachedToken;
final Map<String, String> _avatarCache = {};
final Map<String, File> _voiceCache = {};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  final themeModeString = prefs.getString('theme_mode');
  final themeMode = themeModeString == 'dark'
      ? ThemeMode.dark
      : themeModeString == 'light'
          ? ThemeMode.light
          : ThemeMode.system;

  runApp(DumbApp(themeMode: themeMode));
}

class DumbApp extends StatefulWidget {
  final ThemeMode themeMode;
  const DumbApp({super.key, required this.themeMode});

  @override
  State<DumbApp> createState() => _DumbAppState();
}

class _DumbAppState extends State<DumbApp> {
  Locale? _locale;
  ThemeMode _themeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
    _loadToken();
  }

  void _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString('token');
  }

  void setLocale(Locale locale) {
    setState(() => _locale = locale);
  }

  void setTheme(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _themeMode = mode);
    await prefs.setString('theme_mode',
        mode == ThemeMode.dark ? 'dark' : mode == ThemeMode.light ? 'light' : 'system');
  }

  void setServerUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => apiUrl = url);
    await prefs.setString('server_url', url);
    await prefs.remove('token');
    _cachedToken = null;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DUMB Android',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue, brightness: Brightness.dark),
        brightness: Brightness.dark,
      ),
      themeMode: _themeMode,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: _locale,
      home: ServerSelectionScreen(
        setLocale: setLocale,
        setTheme: setTheme,
        setServerUrl: setServerUrl,
        themeMode: _themeMode,
      ),
    );
  }
}

class ServerSelectionScreen extends StatefulWidget {
  final void Function(Locale) setLocale;
  final void Function(ThemeMode) setTheme;
  final void Function(String) setServerUrl;
  final ThemeMode themeMode;

  const ServerSelectionScreen({
    required this.setLocale,
    required this.setTheme,
    required this.setServerUrl,
    required this.themeMode,
  });

  @override
  State<ServerSelectionScreen> createState() => _ServerSelectionScreenState();
}

class _ServerSelectionScreenState extends State<ServerSelectionScreen> {
  List<Map<String, String>> savedServers = [];
  late TextEditingController _nameController;
  late TextEditingController _urlController;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _urlController = TextEditingController();
    _loadSavedServers();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedServers() async {
    final prefs = await SharedPreferences.getInstance();
    final serversJson = prefs.getStringList('saved_servers') ?? [];
    setState(() {
      savedServers = serversJson.map((server) => Map<String, String>.from(json.decode(server))).toList();
    });
  }

  Future<void> _saveServer() async {
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    
    if (name.isEmpty || url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.invalidInput)),
      );
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final newServer = {'name': name, 'url': url};
    final serversJson = prefs.getStringList('saved_servers') ?? [];
    serversJson.add(json.encode(newServer));
    await prefs.setStringList('saved_servers', serversJson);
    
    _nameController.clear();
    _urlController.clear();
    await _loadSavedServers();
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(AppLocalizations.of(context)!.serverSaved)),
    );
  }

  Future<void> _deleteServer(int index) async {
    final prefs = await SharedPreferences.getInstance();
    final serversJson = prefs.getStringList('saved_servers') ?? [];
    serversJson.removeAt(index);
    await prefs.setStringList('saved_servers', serversJson);
    await _loadSavedServers();
  }

  Future<void> _connectToServer(String url) async {
    final uri = Uri.tryParse(url);

    if (url.isEmpty || uri == null || !uri.hasAbsolutePath) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)!.invalidUrl)),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final resp = await http.get(Uri.parse('$url/ping'));
      if (resp.statusCode == 200) {
        widget.setServerUrl(url);
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => AuthGate(
              setLocale: widget.setLocale,
              setTheme: widget.setTheme,
              setServerUrl: widget.setServerUrl,
              themeMode: widget.themeMode,
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.serverUnreachable)),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.connectionError}: $e')),
      );
    } finally {
      setState(() => _loading = false);
    }
  }

  void _showSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.settings),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(AppLocalizations.of(context)!.language),
                trailing: DropdownButton<Locale>(
                  value: Localizations.localeOf(context),
                  onChanged: (Locale? newLocale) {
                    if (newLocale != null) {
                      widget.setLocale(newLocale);
                      Navigator.pop(context);
                    }
                  },
                  items: AppLocalizations.supportedLocales.map((Locale locale) {
                    return DropdownMenuItem<Locale>(
                      value: locale,
                      child: Text(_getLanguageName(locale)),
                    );
                  }).toList(),
                ),
              ),
              ListTile(
                title: Text(AppLocalizations.of(context)!.theme),
                trailing: DropdownButton<ThemeMode>(
                  value: widget.themeMode,
                  onChanged: (ThemeMode? newTheme) {
                    if (newTheme != null) {
                      widget.setTheme(newTheme);
                      Navigator.pop(context);
                    }
                  },
                  items: [
                    DropdownMenuItem(
                      value: ThemeMode.system,
                      child: Text(AppLocalizations.of(context)!.system),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.light,
                      child: Text(AppLocalizations.of(context)!.light),
                    ),
                    DropdownMenuItem(
                      value: ThemeMode.dark,
                      child: Text(AppLocalizations.of(context)!.dark),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.close),
          ),
        ],
      ),
    );
  }

  String _getLanguageName(Locale locale) {
    switch (locale.languageCode) {
      case 'en': return 'English';
      case 'ru': return 'Русский';
      default: return locale.languageCode;
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.selectServer),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettings,
            tooltip: loc.settings,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      decoration: InputDecoration(labelText: loc.serverName),
                    ),
                    TextField(
                      controller: _urlController,
                      decoration: InputDecoration(labelText: loc.serverUrl),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _saveServer,
                      child: Text(loc.saveServer),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: savedServers.length,
                    itemBuilder: (context, index) {
                      final server = savedServers[index];
                      return ListTile(
                        title: Text(server['name'] ?? ''),
                        subtitle: Text(server['url'] ?? ''),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteServer(index),
                        ),
                        onTap: () => _connectToServer(server['url']!),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  final void Function(Locale) setLocale;
  final void Function(ThemeMode) setTheme;
  final void Function(String) setServerUrl;
  final ThemeMode themeMode;

  const AuthGate({
    required this.setLocale,
    required this.setTheme,
    required this.setServerUrl,
    required this.themeMode,
  });

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  String? token;
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _loadToken();
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString('token');
    _cachedToken = token;
    if (token != null) {
      try {
        final resp = await http.get(
          Uri.parse('$apiUrl/channels'),
          headers: {'Authorization': 'Bearer $token'},
        );
        final json = jsonDecode(resp.body);
        if (resp.statusCode == 200 && json['success'] == true) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => ChannelsScreen(
                token: token!,
                setLocale: widget.setLocale,
                setTheme: widget.setTheme,
                setServerUrl: widget.setServerUrl,
                themeMode: widget.themeMode,
              ),
            ),
          );
          return;
        }
      } catch (e) {}
      prefs.remove('token');
      _cachedToken = null;
    }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return loading
        ? Scaffold(body: Center(child: Text(AppLocalizations.of(context)!.loading)))
        : AuthScreen(onLogin: (t) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('token', t);
            _cachedToken = t;
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (_) => ChannelsScreen(
                  token: t,
                  setLocale: widget.setLocale,
                  setTheme: widget.setTheme,
                  setServerUrl: widget.setServerUrl,
                  themeMode: widget.themeMode,
                ),
              ),
            );
          });
  }
}

class AuthScreen extends StatefulWidget {
  final void Function(String token) onLogin;
  const AuthScreen({required this.onLogin});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  String username = '', password = '', twoFactorToken = '';
  bool isLogin = true;
  bool loading = false, requires2FA = false;
  String error = '', sessionId = '';

  void _auth() async {
    setState(() {
      loading = true;
      error = '';
    });
    final url = isLogin ? '$apiUrl/login' : '$apiUrl/register';
    final resp = await http.post(
      Uri.parse(url),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'password': password,
        if (requires2FA) 'twoFactorToken': twoFactorToken
      }),
    );
    final json = jsonDecode(resp.body);
    if (resp.statusCode != 200 || json['success'] != true) {
      if (json['requires2FA'] == true) {
        setState(() {
          requires2FA = true;
          sessionId = json['sessionId'] ?? '';
          error = json['message'] ?? AppLocalizations.of(context)!.error;
          loading = false;
        });
      } else {
        setState(() {
          error = json['error'] ?? AppLocalizations.of(context)!.error;
          loading = false;
        });
      }
      return;
    }
    if (json['token'] != null) {
      widget.onLogin(json['token']);
    } else if (json['requires2FA'] == true) {
      setState(() => requires2FA = true);
    } else {
      setState(() {
        error = AppLocalizations.of(context)!.error;
        loading = false;
      });
    }
  }

  void _verify2FA() async {
    setState(() {
      loading = true;
      error = '';
    });
    final resp = await http.post(
      Uri.parse('$apiUrl/2fa/verify-login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'username': username,
        'sessionId': sessionId,
        'twoFactorToken': twoFactorToken
      }),
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true && json['token'] != null) {
      widget.onLogin(json['token']);
    } else {
      setState(() {
        error = json['error'] ?? AppLocalizations.of(context)!.error;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? loc.login : loc.register)),
      body: Center(
        child: SizedBox(
          width: 350,
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(labelText: loc.username),
                    onChanged: (v) => username = v,
                    enabled: !loading,
                  ),
                  TextField(
                    decoration: InputDecoration(labelText: loc.password),
                    obscureText: true,
                    onChanged: (v) => password = v,
                    enabled: !loading,
                  ),
                  if (requires2FA)
                    TextField(
                      decoration: const InputDecoration(labelText: '2FA Code'),
                      onChanged: (v) => twoFactorToken = v,
                      enabled: !loading,
                    ),
                  if (error.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(error, style: const TextStyle(color: Colors.red)),
                    ),
                  const SizedBox(height: 20),
                  loading
                      ? const CircularProgressIndicator()
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            ElevatedButton(
                              onPressed: requires2FA ? _verify2FA : _auth,
                              child: Text(requires2FA ? '2FA' : isLogin ? loc.login : loc.register),
                            ),
                            TextButton(
                              onPressed: loading
                                  ? null
                                  : () => setState(() {
                                        isLogin = !isLogin;
                                        error = '';
                                        requires2FA = false;
                                      }),
                              child: Text(isLogin ? loc.register : loc.login),
                            ),
                          ],
                        ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ChannelsScreen extends StatefulWidget {
  final String token;
  final void Function(Locale) setLocale;
  final void Function(ThemeMode) setTheme;
  final void Function(String) setServerUrl;
  final ThemeMode themeMode;

  const ChannelsScreen({
    required this.token,
    required this.setLocale,
    required this.setTheme,
    required this.setServerUrl,
    required this.themeMode,
  });

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List channels = [];
  String error = '';
  bool loading = true;
  WebSocketChannel? _channel;

  @override
  void initState() {
    super.initState();
    _loadChannels();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    try {
      final wsUrl = apiUrl.replaceFirst('http', 'ws').replaceFirst('/api', '');
      final uri = Uri.parse('$wsUrl?token=${_cachedToken}');
      _channel = WebSocketChannel.connect(uri);
      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'message' && data['action'] == 'new') {
            _loadChannels();
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
        },
        onDone: () {
          print('WebSocket closed');
          Future.delayed(const Duration(seconds: 5), _connectWebSocket);
        },
      );
    } catch (e) {
      print('WebSocket connection failed: $e');
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> _loadChannels() async {
    setState(() => loading = true);
    final resp = await http.get(
      Uri.parse('$apiUrl/channels'),
      headers: {'Authorization': 'Bearer ${widget.token}'},
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() {
        channels = json['channels'] ?? [];
        loading = false;
      });
    } else {
      setState(() {
        error = json['error'] ?? AppLocalizations.of(context)!.error;
        loading = false;
      });
    }
  }

  void _createChannel() {
    showDialog(
      context: context,
      builder: (context) => CreateChannelDialog(
        token: widget.token,
        onChannelCreated: _loadChannels,
      ),
    );
  }

  void _searchChannels() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchChannelsScreen(
          token: widget.token,
          onChannelJoined: _loadChannels,
        ),
      ),
    );
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    _cachedToken = null;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => ServerSelectionScreen(
          setLocale: widget.setLocale,
          setTheme: widget.setTheme,
          setServerUrl: widget.setServerUrl,
          themeMode: widget.themeMode,
        ),
      ),
    );
  }

  void _showProfileSettings() {
    showDialog(
      context: context,
      builder: (context) => ProfileSettingsDialog(token: widget.token),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.channels),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _searchChannels,
            tooltip: loc.search,
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createChannel,
            tooltip: loc.createChannel,
          ),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: _showProfileSettings,
            tooltip: loc.profile,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
            tooltip: loc.logout,
          ),
        ],
      ),
      body: loading
          ? Center(child: Text(loc.loading))
          : Column(children: [
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(error, style: const TextStyle(color: Colors.red)),
                ),
              Expanded(
                child: channels.isEmpty
                    ? Center(child: Text(loc.noChannelsAvailable))
                    : ListView.builder(
                        itemCount: channels.length,
                        itemBuilder: (_, i) => ListTile(
                          title: Text(channels[i]['name'] ?? ''),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => ChatScreen(token: widget.token, channel: channels[i]['name']),
                            ),
                          ),
                        ),
                      ),
              ),
            ]),
    );
  }
}

class ProfileSettingsDialog extends StatefulWidget {
  final String token;
  const ProfileSettingsDialog({required this.token});

  @override
  State<ProfileSettingsDialog> createState() => _ProfileSettingsDialogState();
}

class _ProfileSettingsDialogState extends State<ProfileSettingsDialog> {
  bool loading = false;
  String error = '';

  Future<void> _uploadAvatar() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    setState(() {
      loading = true;
      error = '';
    });

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiUrl/upload/avatar'),
      );
      request.headers['Authorization'] = 'Bearer ${widget.token}';
      request.files.add(await http.MultipartFile.fromPath(
        'avatar',
        result.files.single.path!,
      ));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var json = jsonDecode(responseData);

      if (json['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Avatar updated successfully')),
        );
        Navigator.pop(context);
      } else {
        setState(() {
          error = json['error'] ?? 'Failed to upload avatar';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error uploading avatar: $e';
      });
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.profile),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(error, style: const TextStyle(color: Colors.red)),
            ),
          ElevatedButton(
            onPressed: loading ? null : _uploadAvatar,
            child: loading 
                ? const CircularProgressIndicator()
                : const Text('Change Avatar'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.close),
        ),
      ],
    );
  }
}

class CreateChannelDialog extends StatefulWidget {
  final String token;
  final VoidCallback onChannelCreated;

  const CreateChannelDialog({required this.token, required this.onChannelCreated});

  @override
  State<CreateChannelDialog> createState() => _CreateChannelDialogState();
}

class _CreateChannelDialogState extends State<CreateChannelDialog> {
  String channelName = '';
  bool creating = false;
  String error = '';

  Future<void> _createChannel() async {
    if (channelName.isEmpty) return;
    setState(() => creating = true);
    final resp = await http.post(
      Uri.parse('$apiUrl/channels/create'),
      headers: {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'name': channelName}),
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      widget.onChannelCreated();
      Navigator.pop(context);
    } else {
      setState(() {
        error = json['error'] ?? '';
        creating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.createChannel),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: InputDecoration(labelText: AppLocalizations.of(context)!.channelName),
            onChanged: (v) => channelName = v,
          ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(error, style: const TextStyle(color: Colors.red)),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: creating ? null : _createChannel,
          child: creating ? const CircularProgressIndicator() : Text(AppLocalizations.of(context)!.create),
        ),
      ],
    );
  }
}

class SearchChannelsScreen extends StatefulWidget {
  final String token;
  final VoidCallback onChannelJoined;

  const SearchChannelsScreen({required this.token, required this.onChannelJoined});

  @override
  State<SearchChannelsScreen> createState() => _SearchChannelsScreenState();
}

class _SearchChannelsScreenState extends State<SearchChannelsScreen> {
  List channels = [];
  String search = '', error = '';
  bool loading = false;
  WebSocketChannel? _channel;

  @override
  void initState() {
    super.initState();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    try {
      final wsUrl = apiUrl.replaceFirst('http', 'ws').replaceFirst('/api', '');
      final uri = Uri.parse('$wsUrl?token=${_cachedToken}');
      _channel = WebSocketChannel.connect(uri);
      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'message' && data['action'] == 'new') {
            if (search.isNotEmpty) {
              _searchChannels();
            }
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
        },
        onDone: () {
          print('WebSocket closed');
          Future.delayed(const Duration(seconds: 5), _connectWebSocket);
        },
      );
    } catch (e) {
      print('WebSocket connection failed: $e');
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> _searchChannels() async {
    if (search.isEmpty) return;
    setState(() => loading = true);
    final resp = await http.post(
      Uri.parse('$apiUrl/channels/search'),
      headers: {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'query': search}),
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() {
        channels = json['channels'] ?? [];
        loading = false;
      });
    } else {
      setState(() {
        error = json['error'] ?? AppLocalizations.of(context)!.error;
        loading = false;
      });
    }
  }

  Future<void> _joinChannel(String channelName) async {
    final resp = await http.post(
      Uri.parse('$apiUrl/channels/join'),
      headers: {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'channel': channelName}),
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      widget.onChannelJoined();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.join} $channelName')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(json['error'] ?? 'Join failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(loc.search)),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(labelText: loc.search),
                onChanged: (v) => search = v,
                onSubmitted: (_) => _searchChannels(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: _searchChannels,
            ),
          ]),
        ),
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(error, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: loading
              ? Center(child: Text(loc.loading))
              : channels.isEmpty
                  ? Center(child: Text(loc.noChannelsAvailable))
                  : ListView.builder(
                      itemCount: channels.length,
                      itemBuilder: (_, i) => ListTile(
                        title: Text(channels[i]['name'] ?? ''),
                        trailing: ElevatedButton(
                          onPressed: () => _joinChannel(channels[i]['name']),
                          child: Text(loc.join),
                        ),
                      ),
                    ),
        ),
      ]),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String token, channel;

  const ChatScreen({required this.token, required this.channel});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List messages = [];
  String text = '', error = '';
  bool loading = true, sending = false;
  ScrollController scrollController = ScrollController();
  final AudioRecorder _record = AudioRecorder();
  bool _isRecording = false;
  String? _audioPath;
  WebSocketChannel? _wsChannel;
  final Map<String, String> _channelAvatarCache = {};
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _connectWebSocket();
    _preloadChannelAvatars();
  }

  void _preloadChannelAvatars() async {
    final resp = await http.get(
      Uri.parse('$apiUrl/channels/members?channel=${Uri.encodeComponent(widget.channel)}'),
      headers: {'Authorization': 'Bearer ${widget.token}'},
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      final members = List<String>.from(json['members'] ?? []);
      for (final member in members) {
        if (!_avatarCache.containsKey(member)) {
          _loadUserAvatar(member);
        }
      }
    }
  }

  void _loadUserAvatar(String username) async {
    if (_avatarCache.containsKey(username)) return;
    try {
      final avatarUrl = '$apiUrl/user/$username/avatar?${DateTime.now().millisecondsSinceEpoch}';
      final response = await http.get(Uri.parse(avatarUrl));
      if (response.statusCode == 200) {
        _avatarCache[username] = avatarUrl;
      }
    } catch (e) {
      print('Failed to load avatar for $username: $e');
    }
  }

  void _connectWebSocket() {
    try {
      final wsUrl = apiUrl.replaceFirst('http', 'ws').replaceFirst('/api', '');
      final uri = Uri.parse('$wsUrl?token=${_cachedToken}');
      _wsChannel = WebSocketChannel.connect(uri);
      _wsChannel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'message' &&
              data['action'] == 'new' &&
              data['channel'] == widget.channel) {
            final username = data['from'];
            if (username != null && !_avatarCache.containsKey(username)) {
              _loadUserAvatar(username);
            }
            setState(() {
              messages.add(data);
            });
            _scrollToBottom();
          }
        },
        onError: (error) {
          print('WebSocket error: $error');
        },
        onDone: () {
          print('WebSocket closed');
          Future.delayed(const Duration(seconds: 5), _connectWebSocket);
        },
      );
    } catch (e) {
      print('WebSocket connection failed: $e');
    }
  }

  @override
  void dispose() {
    _record.dispose();
    _audioPlayer.dispose();
    _wsChannel?.sink.close();
    super.dispose();
  }

  Future<void> _loadMessages() async {
    final resp = await http.get(
      Uri.parse('$apiUrl/messages?channel=${Uri.encodeComponent(widget.channel)}'),
      headers: {'Authorization': 'Bearer ${widget.token}'},
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      final loadedMessages = json['messages'] ?? [];
      for (final msg in loadedMessages) {
        final username = msg['from'];
        if (username != null && !_avatarCache.containsKey(username)) {
          _loadUserAvatar(username);
        }
      }
      setState(() {
        messages = loadedMessages;
        loading = false;
      });
      _scrollToBottom();
    } else {
      setState(() {
        error = json['error'] ?? AppLocalizations.of(context)!.error;
        loading = false;
      });
    }
  }

  void _scrollToBottom() {
    if (scrollController.hasClients) {
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    }
  }

  Future<void> _sendMessage() async {
    if (text.isEmpty) return;
    setState(() => sending = true);
    final resp = await http.post(
      Uri.parse('$apiUrl/message'),
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
      body: jsonEncode({'channel': widget.channel, 'text': text}),
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() => text = '');
    } else {
      setState(() => error = json['error'] ?? AppLocalizations.of(context)!.error);
    }
    setState(() => sending = false);
  }

  Future<void> _sendFile() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.any);
    if (res == null || res.files.isEmpty) return;
    final pf = res.files.single;
    final mimeType = lookupMimeType(pf.name) ?? '';
    final isMedia = mimeType.startsWith('image/') || mimeType.startsWith('video/');
    final saveDir = await getDumbFolder(media: isMedia);
    final sourceFile = File(pf.path!);
    final savedFile = await sourceFile.copy('$saveDir/${pf.name}');
    var req = http.MultipartRequest('POST', Uri.parse('$apiUrl/upload/file'));
    req.headers['Authorization'] = 'Bearer ${widget.token}';
    req.files.add(await http.MultipartFile.fromPath('file', savedFile.path));
    var resp = await req.send();
    var json = jsonDecode(await resp.stream.bytesToString());
    if (json['success'] == true) {
      final fileId = json['file']['id'];
      await http.post(
        Uri.parse('$apiUrl/message'),
        headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
        body: jsonEncode({'channel': widget.channel, 'fileId': fileId}),
      );
    } else {
      setState(() => error = json['error'] ?? AppLocalizations.of(context)!.error);
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _record.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        _audioPath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.ogg';
        await _record.start(
          RecordConfig(
            encoder: AudioEncoder.opus,
            bitRate: 128000,
            sampleRate: 48000,
          ),
          path: _audioPath!,
        );
        setState(() {
          _isRecording = true;
          error = '';
        });
      } else {
        setState(() => error = 'No audio recording permission');
      }
    } catch (e) {
      print('Recording start error: $e');
      setState(() => error = 'Recording start error: $e');
    }
  }

  Future<void> _stopRecordingAndSend() async {
    try {
      if (!_isRecording) return;
      final path = await _record.stop();
      setState(() => _isRecording = false);
      if (path == null) {
        setState(() => error = 'Failed to save recording');
        return;
      }
      final file = File(path);
      if (!file.existsSync()) {
        setState(() => error = 'Recording file not found');
        return;
      }
      final fileSize = await file.length();
      if (fileSize == 0) {
        setState(() => error = 'Recording is empty');
        return;
      }
      final cacheDir = await getApplicationDocumentsDirectory();
      final cachedPath = '${cacheDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.ogg';
      final cachedFile = await file.copy(cachedPath);
      _voiceCache[cachedPath] = cachedFile;
      var req = http.MultipartRequest('POST', Uri.parse('$apiUrl/upload/file'));
      req.headers['Authorization'] = 'Bearer ${widget.token}';
      req.files.add(await http.MultipartFile.fromPath('file', cachedPath));
      var resp = await req.send();
      var json = jsonDecode(await resp.stream.bytesToString());
      if (json['success'] == true) {
        final fileId = json['file']['id'];
        await http.post(
          Uri.parse('$apiUrl/message'),
          headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
          body: jsonEncode({'channel': widget.channel, 'fileId': fileId}),
        );
      } else {
        setState(() => error = json['error'] ?? 'Voice upload error');
      }
    } catch (e) {
      print('Recording stop/send error: $e');
      setState(() => error = 'Recording send error: $e');
    }
  }

  Future<void> _playVoiceMessage(String filename) async {
    try {
      // Проверяем, есть ли файл в кэше
      final cachedPath = _voiceCache.keys.firstWhere(
        (key) => key.contains(filename) || key.endsWith('/$filename'),
        orElse: () => '',
      );
      
      if (cachedPath.isNotEmpty && await File(cachedPath).exists()) {
        await _audioPlayer.setFilePath(cachedPath);
        await _audioPlayer.play();
        return;
      }

      // Если нет в кэше, скачиваем и кэшируем
      final response = await http.get(
        Uri.parse('$apiUrl/download/$filename'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );

      if (response.statusCode == 200) {
        final cacheDir = await getApplicationDocumentsDirectory();
        final cachedPath = '${cacheDir.path}/voice_$filename';
        await File(cachedPath).writeAsBytes(response.bodyBytes);
        _voiceCache[cachedPath] = File(cachedPath);
        
        await _audioPlayer.setFilePath(cachedPath);
        await _audioPlayer.play();
      } else {
        setState(() => error = 'Failed to download voice message');
      }
    } catch (e) {
      print('Voice playback error: $e');
      setState(() => error = 'Voice playback error: $e');
    }
  }

  Widget _buildFileMessage(Map<String, dynamic> file) {
    final filename = file['filename'] ?? '';
    final originalName = file['originalName'] ?? '';
    final mimeType = file['mimetype'] ?? '';
    final downloadUrl = file['downloadUrl'] ?? '';

    // Проверяем, является ли файл голосовым сообщением
    final isVoiceMessage = filename.toLowerCase().endsWith('.ogg') || 
                          originalName.toLowerCase().endsWith('.ogg') ||
                          mimeType.contains('audio/ogg');

    if (isVoiceMessage) {
      return GestureDetector(
        onTap: () => _playVoiceMessage(filename),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.play_arrow, color: Colors.blue, size: 24),
              const SizedBox(width: 8),
              const Text('Voice message', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 8),
              Text('${(file['size'] ?? 0) ~/ 1024} KB'),
            ],
          ),
        ),
      );
    }

    // Для обычных файлов
    return GestureDetector(
      onTap: () async {
        try {
          final response = await http.get(
            Uri.parse('$apiUrl/download/$filename'),
            headers: {'Authorization': 'Bearer ${widget.token}'},
          );
          
          if (response.statusCode == 200) {
            final dir = await getApplicationDocumentsDirectory();
            final filePath = '${dir.path}/$originalName';
            await File(filePath).writeAsBytes(response.bodyBytes);
            
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('File saved to: $filePath')),
            );
          }
        } catch (e) {
          setState(() => error = 'File download error: $e');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.insert_drive_file, size: 24),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(originalName, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${(file['size'] ?? 0) ~/ 1024} KB'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel)),
      body: Column(children: [
        if (error.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(error, style: const TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: loading
              ? Center(child: Text(loc.loading))
              : messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(loc.noMessages, style: const TextStyle(fontSize: 18)),
                          const SizedBox(height: 8),
                          Text(loc.beFirstToMessage, style: const TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: messages.length,
                      itemBuilder: (_, i) {
                        final msg = messages[i];
                        final username = msg['from'] ?? '';
                        final avatarUrl = _avatarCache[username];
                        final file = msg['file'];
                        
                        return ListTile(
                          leading: avatarUrl != null
                              ? CircleAvatar(backgroundImage: NetworkImage(avatarUrl))
                              : const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(username),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (msg['text'] != null && msg['text'].isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Text(msg['text']),
                                ),
                              if (file != null) _buildFileMessage(file),
                            ],
                          ),
                        );
                      },
                    ),
        ),
        Container(
          padding: const EdgeInsets.all(8.0),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(
                  labelText: loc.typeMessage,
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onChanged: (v) => text = v,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              onPressed: _isRecording ? _stopRecordingAndSend : _startRecording,
              tooltip: _isRecording ? loc.stopRecording : loc.startRecording,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: _sendFile,
              tooltip: loc.sendFile,
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: sending ? const CircularProgressIndicator() : const Icon(Icons.send),
              onPressed: sending ? null : _sendMessage,
              tooltip: loc.send,
            ),
          ]),
        ),
      ]),
    );
  }
}

Future<String> getDumbFolder({bool media = false}) async {
  final dir = await getApplicationDocumentsDirectory();
  final dumbDir = Directory('${dir.path}/dumb');
  if (!dumbDir.existsSync()) dumbDir.createSync(recursive: true);
  if (media) {
    final mediaDir = Directory('${dumbDir.path}/media');
    if (!mediaDir.existsSync()) mediaDir.createSync(recursive: true);
    return mediaDir.path;
  }
  return dumbDir.path;
}
