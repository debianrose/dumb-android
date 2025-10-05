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
import 'l10n/app_localizations.dart';

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

String apiUrl = 'http://localhost:3000/api';
String? _cachedToken;
final Map<String, String> _avatarCache = {};

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
    _loadServerUrl();
    _loadToken();
  }

  void _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString('token');
  }

  void _loadServerUrl() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      apiUrl = prefs.getString('server_url') ?? 'http://localhost:3000/api';
    });
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
      home: AuthGate(
        setLocale: setLocale,
        setTheme: setTheme,
        setServerUrl: setServerUrl,
        themeMode: _themeMode,
      ),
    );
  }
}

class AuthGate extends StatefulWidget {
  final void Function(Locale) setLocale;
  final void Function(ThemeMode) setTheme;
  final void Function(String) setServerUrl;
  final ThemeMode themeMode;
  const AuthGate({required this.setLocale, required this.setTheme, required this.setServerUrl, required this.themeMode});

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
      final resp = await http.get(Uri.parse('$apiUrl/channels'), headers: {'Authorization': 'Bearer $token'});
      if (resp.statusCode == 200 && jsonDecode(resp.body)['success'] == true) {
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
      prefs.remove('token');
      _cachedToken = null;
    }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return loading
        ? Scaffold(body: Center(child: Text(AppLocalizations.of(context)?.loading ?? 'Loading...')))
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
    final resp = await http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'username': username, 'password': password, if (requires2FA) 'twoFactorToken': twoFactorToken}));
    final json = jsonDecode(resp.body);

    if (resp.statusCode != 200 || json['success'] != true) {
      if (json['requires2FA'] == true) {
        setState(() {
          requires2FA = true;
          sessionId = json['sessionId'] ?? '';
          error = json['message'] ?? AppLocalizations.of(context)?.error ?? 'Error';
          loading = false;
        });
      } else {
        setState(() {
          error = json['error'] ?? AppLocalizations.of(context)?.error ?? 'Error';
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
        error = AppLocalizations.of(context)?.error ?? 'Unknown error';
        loading = false;
      });
    }
  }

  void _verify2FA() async {
    setState(() {
      loading = true;
      error = '';
    });
    final resp = await http.post(Uri.parse('$apiUrl/2fa/verify-login'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'username': username, 'sessionId': sessionId, 'twoFactorToken': twoFactorToken}));
    final json = jsonDecode(resp.body);

    if (json['success'] == true && json['token'] != null) {
      widget.onLogin(json['token']);
    } else {
      setState(() {
        error = json['error'] ?? AppLocalizations.of(context)?.error ?? '2FA error';
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
              child: Column(mainAxisSize: MainAxisSize.min, children: [
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
                    decoration: InputDecoration(labelText: '2FA Code'),
                    onChanged: (v) => twoFactorToken = v,
                    enabled: !loading,
                  ),
                if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error, style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 20),
                loading
                    ? const CircularProgressIndicator()
                    : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
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
                      ]),
              ]),
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
          Future.delayed(Duration(seconds: 5), _connectWebSocket);
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
    final resp = await http.get(Uri.parse('$apiUrl/channels'), headers: {'Authorization': 'Bearer ${widget.token}'});
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() {
        channels = json['channels'] ?? [];
        loading = false;
      });
    } else {
      setState(() {
        error = json['error'] ?? AppLocalizations.of(context)?.error ?? 'Error';
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
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SettingsScreen(
                  token: widget.token,
                  setLocale: widget.setLocale,
                  setTheme: widget.setTheme,
                  setServerUrl: widget.setServerUrl,
                  themeMode: widget.themeMode,
                ),
              ),
            ),
          ),
        ],
      ),
      body: loading
          ? Center(child: Text(loc.loading))
          : Column(children: [
              if (error.isNotEmpty) 
                Padding(padding: const EdgeInsets.all(8.0), child: Text(error, style: const TextStyle(color: Colors.red))),
              Expanded(
                child: ListView.builder(
                  itemCount: channels.length,
                  itemBuilder: (_, i) => ListTile(
                    title: Text(channels[i]['name'] ?? ''),
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(token: widget.token, channel: channels[i]['name']))),
                  ),
                ),
              ),
            ]),
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
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'}, 
      body: jsonEncode({'name': channelName})
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
            Padding(padding: const EdgeInsets.only(top: 10), child: Text(error, style: const TextStyle(color: Colors.red))),
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
          Future.delayed(Duration(seconds: 5), _connectWebSocket);
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
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'}, 
      body: jsonEncode({'query': search})
    );
    final json = jsonDecode(resp.body);
    
    if (json['success'] == true) {
      setState(() {
        channels = json['channels'] ?? [];
        loading = false;
      });
    } else {
      setState(() {
        error = json['error'] ?? AppLocalizations.of(context)?.error ?? 'Error';
        loading = false;
      });
    }
  }

  Future<void> _joinChannel(String channelName) async {
    final resp = await http.post(
      Uri.parse('$apiUrl/channels/join'), 
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'}, 
      body: jsonEncode({'channel': channelName})
    );
    final json = jsonDecode(resp.body);
    
    if (json['success'] == true) {
      widget.onChannelJoined();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Joined $channelName'))
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(json['error'] ?? 'Join failed'))
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
          Padding(padding: const EdgeInsets.all(8.0), child: Text(error, style: const TextStyle(color: Colors.red))),
        Expanded(
          child: loading 
            ? Center(child: Text(loc.loading))
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
          if (data['type'] == 'message' && data['action'] == 'new' && data['channel'] == widget.channel) {
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
          Future.delayed(Duration(seconds: 5), _connectWebSocket);
        },
      );
    } catch (e) {
      print('WebSocket connection failed: $e');
    }
  }

  @override
  void dispose() {
    _record.dispose();
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
        error = json['error'] ?? AppLocalizations.of(context)?.error ?? 'Error';
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
      body: jsonEncode({'channel': widget.channel, 'text': text})
    );
    final json = jsonDecode(resp.body);
    
    if (json['success'] == true) {
      setState(() => text = '');
    } else {
      setState(() => error = json['error'] ?? AppLocalizations.of(context)?.error ?? 'Send error');
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
        body: jsonEncode({'channel': widget.channel, 'fileId': fileId})
      );
    } else {
      setState(() => error = json['error'] ?? AppLocalizations.of(context)?.error ?? 'File upload error');
    }
  }

  Future<void> _startRecording() async {
  try {
    if (await _record.hasPermission()) {
      final tempDir = await getTemporaryDirectory();
      _audioPath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.ogg';
      
         // Явное указание Opus кодеков
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
      print('🎯 Запись начата: $_audioPath');
    } else {
      setState(() => error = 'Нет разрешения на запись аудио');
    }
  } catch (e) {
    print('Recording start error: $e');
    setState(() => error = 'Ошибка начала записи: $e');
  }
}

  Future<void> _stopRecordingAndSend() async {
    try {
      if (!_isRecording) return;
      
      final path = await _record.stop();
      setState(() => _isRecording = false);
      
      if (path == null) {
        setState(() => error = 'Не удалось сохранить запись');
        return;
      }

      final file = File(path);
      
      if (!file.existsSync()) {
        setState(() => error = 'Файл записи не найден');
        return;
      }

      final fileSize = await file.length();
      print('🎯 Размер записанного файла: $fileSize байт');
      
      if (fileSize < 100) {
        setState(() => error = 'Запись пуста или слишком короткая');
        await file.delete();
        return;
      }

      print('🎯 Шаг 1: Инициализация голосового сообщения...');
      final initResponse = await http.post(
        Uri.parse('$apiUrl/voice/upload'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({
          'channel': widget.channel,
          'duration': 0
        }),
      );

      print('🎯 Init response status: ${initResponse.statusCode}');
      print('🎯 Init response body: ${initResponse.body}');

      if (initResponse.statusCode != 200) {
        setState(() => error = 'Ошибка инициализации: ${initResponse.statusCode}');
        await file.delete();
        return;
      }

      final initJson = jsonDecode(initResponse.body);
      if (initJson['success'] != true) {
        setState(() => error = initJson['error'] ?? 'Ошибка инициализации');
        await file.delete();
        return;
      }

      final voiceId = initJson['voiceId'];
      final uploadUrl = initJson['uploadUrl'];

      print('🎯 Voice ID: $voiceId');
      print('🎯 Upload URL: $uploadUrl');

      print('🎯 Шаг 2: Загрузка аудиофайла...');
      
      String fullUploadUrl;
      if (uploadUrl.startsWith('/')) {
        fullUploadUrl = apiUrl.replaceFirst('/api', '') + uploadUrl;
      } else {
        fullUploadUrl = '$apiUrl$uploadUrl';
      }
      
      print('🎯 Full upload URL: $fullUploadUrl');
      
      try {
        var request = http.MultipartRequest('POST', Uri.parse(fullUploadUrl));
        request.headers['Authorization'] = 'Bearer ${widget.token}';
        
        request.files.add(await http.MultipartFile.fromPath(
          'voice',
          path,
          filename: voiceId,
        ));

        final uploadResponse = await request.send();
        final responseBody = await uploadResponse.stream.bytesToString();
        
        print('🎯 Upload response status: ${uploadResponse.statusCode}');
        print('🎯 Upload response body: $responseBody');
        
        if (uploadResponse.statusCode != 200) {
          setState(() => error = 'Ошибка загрузки файла: ${uploadResponse.statusCode}');
          await file.delete();
          return;
        }

        final uploadJson = jsonDecode(responseBody);
        if (uploadJson['success'] != true) {
          setState(() => error = uploadJson['error'] ?? 'Ошибка загрузки файла');
          await file.delete();
          return;
        }

        print('🎯 Файл успешно загружен!');

        print('🎯 Шаг 3: Отправка голосового сообщения...');
        final sendResponse = await http.post(
          Uri.parse('$apiUrl/message/voice-only'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({
            'channel': widget.channel,
            'voiceMessage': voiceId
          }),
        );

        print('🎯 Send response status: ${sendResponse.statusCode}');
        print('🎯 Send response body: ${sendResponse.body}');

        final sendJson = jsonDecode(sendResponse.body);
        
        if (sendJson['success'] == true) {
          print('🎯 Голосовое сообщение отправлено успешно!');
          setState(() => error = '');
          _loadMessages();
        } else {
          setState(() => error = sendJson['error'] ?? 'Ошибка отправки сообщения');
        }

      } catch (uploadError) {
        print('🎯 Ошибка при загрузке файла: $uploadError');
        setState(() => error = 'Ошибка загрузки: $uploadError');
      }

      await file.delete();
      _audioPath = null;
      
    } catch (e) {
      print('🎯 Общая ошибка отправки голоса: $e');
      setState(() => error = 'Ошибка отправки голоса: $e');
    }
  }

  Future<void> _playVoice(String url) async {
    try {
      final player = AudioPlayer();
      
      String fullUrl;
      if (url.startsWith('/')) {
        fullUrl = apiUrl.replaceFirst('/api', '') + url;
      } else if (url.startsWith('http')) {
        fullUrl = url;
      } else {
        fullUrl = apiUrl.replaceFirst('/api', '') + '/api/download/' + url;
      }
      
      print('🎯 Playing voice from: $fullUrl');
      
      await player.setUrl(fullUrl);
      await player.play();
      
      player.playerStateStream.listen((state) async {
        if (state.processingState == ProcessingState.completed) {
          await player.dispose();
        }
      });
      
      Future.delayed(Duration(seconds: 30), () async {
        if (player.playing) {
          await player.stop();
        }
        await player.dispose();
      });
      
    } catch (e) {
      print('Voice play error: $e');
      setState(() => error = 'Ошибка воспроизведения: $e');
    }
  }

  void _viewImage(String url, String filename) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Stack(
          children: [
            InteractiveViewer(
              child: Image.network(apiUrl.replaceFirst('/api', '') + url),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: IconButton(
                icon: Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageFile(Map file) {
    final mime = file['mimetype'] ?? '';
    final url = file['downloadUrl'];
    final filename = file['originalName'] ?? 'file';
    
    final isVoiceMessage = filename.endsWith('.ogg') || 
                      filename.endsWith('.opus') || 
                      mime.contains('audio/ogg') ||
                      mime.contains('audio/opus');    

    if (isVoiceMessage) {
      return GestureDetector(
        onTap: () => _playVoice(url),
        child: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow, color: Colors.blue),
              SizedBox(width: 8),
              Text('Голосовое сообщение'),
            ],
          ),
        ),
      );
    }

    if (mime.startsWith('image/')) {
      return GestureDetector(
        onTap: () => _viewImage(url, filename),
        child: Image.network(apiUrl.replaceFirst('/api', '') + url, width: 200),
      );
    }

    if (mime.startsWith('video/')) {
      return GestureDetector(
        onTap: () => _playVideo(url),
        child: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow, color: Colors.red),
              SizedBox(width: 8),
              Text('Видео: $filename'),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _downloadFile(url, filename),
      child: Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.insert_drive_file),
            SizedBox(width: 8),
            Text(filename),
          ],
        ),
      ),
    );
  }

  Future<void> _playVideo(String url) async {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Воспроизведение видео будет реализовано позже'))
    );
  }

  Future<void> _downloadFile(String url, String filename) async {
    try {
      final response = await http.get(Uri.parse(apiUrl.replaceFirst('/api', '') + url));
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(response.bodyBytes);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Файл сохранен: ${file.path}'))
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка загрузки: $e'))
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(widget.channel)),
      body: Column(children: [
        if (error.isNotEmpty) 
          Padding(padding: const EdgeInsets.all(8.0), child: Text(error, style: const TextStyle(color: Colors.red))),
        Expanded(
          child: loading
              ? Center(child: Text(loc.loading))
              : ListView.builder(
                  controller: scrollController,
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    final username = msg['from'];
                    final avatarUrl = username != null ? _avatarCache[username] : null;
                    
                    return ListTile(
                      leading: avatarUrl != null 
                          ? CircleAvatar(backgroundImage: NetworkImage(avatarUrl))
                          : CircleAvatar(child: Text(username?.substring(0, 1) ?? '?')),
                      title: Text(username ?? ''),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (msg['text'] != null && msg['text'].isNotEmpty) 
                            Text(msg['text']),
                          if (msg['file'] != null) 
                            _buildMessageFile(msg['file']),
                          if (msg['voiceMessage'] != null)
                            GestureDetector(
                              onTap: () => _playVoice(msg['voiceMessage']),
                              child: Container(
                                padding: EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blue.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.play_arrow, color: Colors.blue),
                                    SizedBox(width: 8),
                                    Text('Голосовое сообщение'),
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
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(children: [
            Expanded(
              child: TextField(
                decoration: InputDecoration(labelText: loc.typeMessage),
                onChanged: (v) => text = v,
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            IconButton(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              onPressed: _isRecording ? _stopRecordingAndSend : _startRecording,
              tooltip: _isRecording ? 'Остановить запись' : 'Записать голосовое сообщение',
            ),
            IconButton(
              icon: const Icon(Icons.attach_file), 
              onPressed: _sendFile,
            ),
            IconButton(
              icon: sending ? const CircularProgressIndicator() : const Icon(Icons.send), 
              onPressed: sending ? null : _sendMessage,
            ),
          ]),
        ),
      ]),
    );
  }
}

class SettingsScreen extends StatefulWidget {
  final String token;
  final void Function(Locale) setLocale;
  final void Function(ThemeMode) setTheme;
  final void Function(String) setServerUrl;
  final ThemeMode themeMode;
  const SettingsScreen({required this.token, required this.setLocale, required this.setTheme, required this.setServerUrl, required this.themeMode});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String username = '', email = '', error = '', serverUrl = apiUrl;
  bool loading = true, twoFactorEnabled = false;
  String twoFactorSecret = '', twoFactorQrCode = '';
  Locale? selectedLocale;
  ThemeMode selectedThemeMode = ThemeMode.system;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    serverUrl = apiUrl;
    selectedThemeMode = widget.themeMode;
  }

  Future<void> _loadProfile() async {
    final resp = await http.get(Uri.parse('$apiUrl/user/profile'), headers: {'Authorization': 'Bearer ${widget.token}'});
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() {
        username = json['user']['username'] ?? '';
        email = json['user']['email'] ?? '';
        twoFactorEnabled = json['user']['twoFactorEnabled'] ?? false;
        loading = false;
      });
    } else {
      setState(() {
        error = json['error'] ?? AppLocalizations.of(context)?.error ?? 'Error';
        loading = false;
      });
    }
  }

  Future<void> _enable2FA() async {
    final resp = await http.post(Uri.parse('$apiUrl/2fa/setup'), headers: {'Authorization': 'Bearer ${widget.token}'});
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() {
        twoFactorSecret = json['secret'] ?? '';
        twoFactorQrCode = json['qrCode'] ?? '';
      });
    } else {
      setState(() => error = json['error'] ?? AppLocalizations.of(context)?.error ?? '2FA setup error');
    }
  }

  Future<void> _disable2FA() async {
    final resp = await http.post(Uri.parse('$apiUrl/2fa/disable'), headers: {'Authorization': 'Bearer ${widget.token}'});
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() => twoFactorEnabled = false);
    } else {
      setState(() => error = json['error'] ?? AppLocalizations.of(context)?.error ?? '2FA disable error');
    }
  }

  void _saveServerUrl() {
    widget.setServerUrl(serverUrl);
    apiUrl = serverUrl;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('URL сервера обновлен'))
    );
  }

  void _changeLanguage(Locale? locale) {
    if (locale != null) {
      widget.setLocale(locale);
      setState(() => selectedLocale = locale);
    }
  }

  void _changeTheme(ThemeMode? mode) {
    if (mode != null) {
      widget.setTheme(mode);
      setState(() => selectedThemeMode = mode);
    }
  }

  void _logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    _cachedToken = null;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => AuthGate(
      setLocale: widget.setLocale,
      setTheme: widget.setTheme,
      setServerUrl: widget.setServerUrl,
      themeMode: widget.themeMode,
    )));
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(loc.settings)),
      body: loading
          ? Center(child: Text(loc.loading))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(loc.profile, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: username,
                  decoration: InputDecoration(labelText: loc.username),
                  readOnly: true,
                ),
                TextFormField(
                  initialValue: email,
                  decoration: InputDecoration(labelText: 'Email'),
                  readOnly: true,
                ),
                const SizedBox(height: 24),
                Text('Двухфакторная аутентификация', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                if (twoFactorEnabled)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('2FA включена'),
                      ElevatedButton(
                        onPressed: _disable2FA,
                        child: Text('Отключить 2FA'),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('2FA отключена'),
                      ElevatedButton(
                        onPressed: _enable2FA,
                        child: Text('Включить 2FA'),
                      ),
                      if (twoFactorQrCode.isNotEmpty) Image.network(twoFactorQrCode),
                      if (twoFactorSecret.isNotEmpty) Text('Secret: $twoFactorSecret'),
                    ],
                  ),
                const SizedBox(height: 24),
                Text('Внешний вид', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                DropdownButtonFormField<Locale>(
                  value: selectedLocale,
                  items: AppLocalizations.supportedLocales.map((locale) {
                    return DropdownMenuItem(
                      value: locale,
                      child: Text('${locale.languageCode.toUpperCase()}'),
                    );
                  }).toList(),
                  onChanged: _changeLanguage,
                  decoration: InputDecoration(labelText: 'Язык'),
                ),
                DropdownButtonFormField<ThemeMode>(
                  value: selectedThemeMode,
                  items: [
                    DropdownMenuItem(value: ThemeMode.system, child: Text('Системная')),
                    DropdownMenuItem(value: ThemeMode.light, child: Text('Светлая')),
                    DropdownMenuItem(value: ThemeMode.dark, child: Text('Темная')),
                  ],
                  onChanged: _changeTheme,
                  decoration: InputDecoration(labelText: 'Тема'),
                ),
                const SizedBox(height: 24),
                Text('Сервер', style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 16),
                TextFormField(
                  initialValue: serverUrl,
                  decoration: InputDecoration(labelText: 'URL сервера'),
                  onChanged: (v) => serverUrl = v,
                ),
                ElevatedButton(
                  onPressed: _saveServerUrl,
                  child: Text('Сохранить'),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _logout,
                  child: Text(loc.logout),
                ),
                if (error.isNotEmpty) 
                  Padding(padding: const EdgeInsets.only(top: 10), child: Text(error, style: const TextStyle(color: Colors.red))),
              ],
            ),
    );
  }
}

Future<String> getDumbFolder({bool media = false}) async {
  final dir = await getApplicationDocumentsDirectory();
  final dumbDir = Directory('${dir.path}/Dumb/${media ? 'Media' : 'Files'}');
  if (!dumbDir.existsSync()) dumbDir.createSync(recursive: true);
  return dumbDir.path;
}
