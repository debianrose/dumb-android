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
import 'package:ogg_opus_player/ogg_opus_player.dart';
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
  OggOpusRecorder? _recorder;
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
    _recorder?.dispose();
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
    final tempDir = await getTemporaryDirectory();
    final workDir = Directory('${tempDir.path}/ogg_opus_recorder');
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    
    _audioPath = '${workDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.ogg';
    
    // Создаем файл и директорию если нужно
    final file = File(_audioPath!);
    if (file.existsSync()) {
      await file.delete();
    }
    await file.create(recursive: true);
    
    _recorder = OggOpusRecorder(_audioPath!);
    await _recorder!.start();
    
    setState(() {
      _isRecording = true;
      error = '';
    });
    print('🎯 Запись начата: $_audioPath');
  } catch (e) {
    print('Recording start error: $e');
    setState(() => error = 'Ошибка начала записи: $e');
  }
}

  Future<void> _stopRecordingAndSend() async {
  try {
    if (_recorder == null) return;
    
    await _recorder!.stop();
    setState(() => _isRecording = false);
    
    final duration = await _recorder!.duration();
    print('🎯 Длительность записи: $duration секунд');
    
    _recorder?.dispose();
    _recorder = null;
    
    if (_audioPath == null) {
      setState(() => error = 'Не удалось сохранить запись');
      return;
    }

    final file = File(_audioPath!);
    
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
        'duration': duration
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
        _audioPath!,
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
    
    // Формируем правильный URL
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
    
    // Слушаем состояние воспроизведения
    player.playerStateStream.listen((state) async {
      if (state.processingState == ProcessingState.completed) {
        await player.dispose();
      }
    });
    
    // Автоматически освобождаем ресурсы через 30 секунд на всякий случай
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
          Icon(Icons.file_download),
          SizedBox(width: 8),
          Text(filename),
        ],
      ),
    ),
  );
}

  Future<void> _playVideo(String url) async {
    // TODO: Implement video player
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Video playback not implemented yet'))
    );
  }

  Future<void> _downloadFile(String url, String filename) async {
    final saveDir = await getDumbFolder(media: false);
    final file = File('$saveDir/$filename');
    final resp = await http.get(Uri.parse(apiUrl.replaceFirst('/api', '') + url));
    await file.writeAsBytes(resp.bodyBytes);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved to ${file.path}'))
    );
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
                  final username = msg['from'] ?? '';
                  final avatarUrl = _avatarCache[username];
                  
                  return ListTile(
                    leading: avatarUrl != null 
                      ? CircleAvatar(backgroundImage: NetworkImage(avatarUrl))
                      : CircleAvatar(child: Text(username.isNotEmpty ? username[0].toUpperCase() : '?')),
                    title: Text(username),
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
                        Text(DateTime.parse(msg['timestamp'] ?? '').toLocal().toString()),
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
                decoration: InputDecoration(labelText: loc.message),
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
            if (sending) const CircularProgressIndicator() else IconButton(icon: const Icon(Icons.send), onPressed: _sendMessage),
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
  const SettingsScreen({
    required this.token,
    required this.setLocale,
    required this.setTheme,
    required this.setServerUrl,
    required this.themeMode,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String username = '', email = '', error = '', serverUrl = apiUrl;
  bool loading = true, twoFactorEnabled = false;
  Uint8List? avatarBytes;
  bool avatarLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final resp = await http.get(Uri.parse('$apiUrl/user'), headers: {'Authorization': 'Bearer ${widget.token}'});
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

  Future<void> _pickAvatar() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res == null || res.files.isEmpty) return;
    final bytes = res.files.single.bytes;
    if (bytes == null) return;
    setState(() => avatarBytes = bytes);
    await _uploadAvatar();
  }

  Future<void> _uploadAvatar() async {
    if (avatarBytes == null) return;
    setState(() => avatarLoading = true);
    var req = http.MultipartRequest('POST', Uri.parse('$apiUrl/user/avatar'));
    req.headers['Authorization'] = 'Bearer ${widget.token}';
    req.files.add(http.MultipartFile.fromBytes('avatar', avatarBytes!, filename: 'avatar.png'));
    var resp = await req.send();
    var json = jsonDecode(await resp.stream.bytesToString());
    if (json['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)?.avatarUpdated ?? 'Avatar updated')));
    } else {
      setState(() => error = json['error'] ?? AppLocalizations.of(context)?.error ?? 'Upload error');
    }
    setState(() => avatarLoading = false);
  }

  void _changePassword() {
    showDialog(
      context: context,
      builder: (context) => ChangePasswordDialog(token: widget.token),
    );
  }

  void _setup2FA() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TwoFactorSetupScreen(token: widget.token),
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
        builder: (_) => AuthGate(
          setLocale: widget.setLocale,
          setTheme: widget.setTheme,
          setServerUrl: widget.setServerUrl,
          themeMode: widget.themeMode,
        ),
      ),
    );
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
                if (error.isNotEmpty) 
                  Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(error, style: const TextStyle(color: Colors.red))),
                Center(
                  child: Column(children: [
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: avatarLoading
                          ? const CircularProgressIndicator()
                          : CircleAvatar(
                              radius: 50,
                              backgroundImage: avatarBytes != null ? MemoryImage(avatarBytes!) : null,
                              child: avatarBytes == null ? const Icon(Icons.person, size: 40) : null,
                            ),
                    ),
                    const SizedBox(height: 16),
                    Text(username, style: Theme.of(context).textTheme.headlineSmall),
                    Text(email),
                  ]),
                ),
                const SizedBox(height: 32),
                ListTile(
                  title: Text(loc.changePassword),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: _changePassword,
                ),
                ListTile(
                  title: Text('2FA ${twoFactorEnabled ? loc.enabled : loc.disabled}'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: _setup2FA,
                ),
                const Divider(),
                ListTile(
                  title: Text(loc.language),
                  subtitle: Text(_getCurrentLanguageName(context)),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () => _showLanguageDialog(context),
                ),
                ListTile(
                  title: Text(loc.theme),
                  subtitle: Text(_getThemeName(widget.themeMode, context)),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () => _showThemeDialog(context),
                ),
                ListTile(
                  title: Text(loc.serverUrl),
                  subtitle: Text(serverUrl),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () => _showServerUrlDialog(context),
                ),
                const Divider(),
                ListTile(
                  title: Text(loc.logout, style: const TextStyle(color: Colors.red)),
                  onTap: _logout,
                ),
              ],
            ),
    );
  }

  String _getCurrentLanguageName(BuildContext context) {
    final locale = Localizations.localeOf(context);
    switch (locale.languageCode) {
      case 'en': return 'English';
      case 'ru': return 'Русский';
      default: return 'English';
    }
  }

  String _getThemeName(ThemeMode mode, BuildContext context) {
    switch (mode) {
      case ThemeMode.light: return AppLocalizations.of(context)!.light;
      case ThemeMode.dark: return AppLocalizations.of(context)!.dark;
      case ThemeMode.system: return AppLocalizations.of(context)!.system;
    }
  }

  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.language),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('English'),
              onTap: () {
                widget.setLocale(const Locale('en'));
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text('Русский'),
              onTap: () {
                widget.setLocale(const Locale('ru'));
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showThemeDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.theme),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(AppLocalizations.of(context)!.light),
              onTap: () {
                widget.setTheme(ThemeMode.light);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text(AppLocalizations.of(context)!.dark),
              onTap: () {
                widget.setTheme(ThemeMode.dark);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: Text(AppLocalizations.of(context)!.system),
              onTap: () {
                widget.setTheme(ThemeMode.system);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showServerUrlDialog(BuildContext context) {
    final controller = TextEditingController(text: serverUrl);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.serverUrl),
        content: TextField(controller: controller),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          ElevatedButton(
            onPressed: () {
              final newUrl = controller.text.trim();
              if (newUrl.isNotEmpty) {
                setState(() => serverUrl = newUrl);
                widget.setServerUrl(newUrl);
                apiUrl = '$newUrl/api';
                Navigator.pop(context);
              }
            },
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
  }
}

class ChangePasswordDialog extends StatefulWidget {
  final String token;
  const ChangePasswordDialog({required this.token});

  @override
  State<ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<ChangePasswordDialog> {
  String currentPassword = '', newPassword = '', error = '';
  bool loading = false;

  Future<void> _changePassword() async {
    if (newPassword.isEmpty) return;
    setState(() => loading = true);
    final resp = await http.post(
      Uri.parse('$apiUrl/user/change-password'), 
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'}, 
      body: jsonEncode({'currentPassword': currentPassword, 'newPassword': newPassword})
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context)?.passwordChanged ?? 'Password changed'))
      );
    } else {
      setState(() {
        error = json['error'] ?? AppLocalizations.of(context)?.error ?? 'Error';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(AppLocalizations.of(context)!.changePassword),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            decoration: InputDecoration(labelText: AppLocalizations.of(context)!.currentPassword),
            obscureText: true,
            onChanged: (v) => currentPassword = v,
          ),
          TextField(
            decoration: InputDecoration(labelText: AppLocalizations.of(context)!.newPassword),
            obscureText: true,
            onChanged: (v) => newPassword = v,
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
          onPressed: loading ? null : _changePassword,
          child: loading ? const CircularProgressIndicator() : Text(AppLocalizations.of(context)!.change),
        ),
      ],
    );
  }
}

class TwoFactorSetupScreen extends StatefulWidget {
  final String token;
  const TwoFactorSetupScreen({required this.token});

  @override
  State<TwoFactorSetupScreen> createState() => _TwoFactorSetupScreenState();
}

class _TwoFactorSetupScreenState extends State<TwoFactorSetupScreen> {
  String qrCodeUrl = '', secret = '', token = '', error = '';
  bool loading = true, verifying = false, twoFactorEnabled = false;

  @override
  void initState() {
    super.initState();
    _load2FASetup();
  }

  Future<void> _load2FASetup() async {
    final resp = await http.get(Uri.parse('$apiUrl/2fa/setup'), headers: {'Authorization': 'Bearer ${widget.token}'});
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() {
        qrCodeUrl = json['qrCodeUrl'] ?? '';
        secret = json['secret'] ?? '';
        loading = false;
      });
    } else {
      setState(() {
        error = json['error'] ?? AppLocalizations.of(context)?.error ?? 'Error';
        loading = false;
      });
    }
  }

  Future<void> _verify2FA() async {
    if (token.isEmpty) return;
    setState(() => verifying = true);
    final resp = await http.post(
      Uri.parse('$apiUrl/2fa/verify'), 
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'}, 
      body: jsonEncode({'token': token})
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() => twoFactorEnabled = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('2FA enabled'))
      );
    } else {
      setState(() {
        error = json['error'] ?? 'Verification failed';
        verifying = false;
      });
    }
  }

  Future<void> _disable2FA() async {
    final resp = await http.post(
      Uri.parse('$apiUrl/2fa/disable'), 
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'}, 
      body: jsonEncode({})
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() => twoFactorEnabled = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('2FA disabled'))
      );
    } else {
      setState(() => error = json['error'] ?? 'Disable failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('2FA Setup')),
      body: loading
          ? Center(child: Text(AppLocalizations.of(context)?.loading ?? 'Loading...'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (error.isNotEmpty) 
                  Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(error, style: const TextStyle(color: Colors.red))),
                if (!twoFactorEnabled) ...[
                  Text('Scan QR code with your authenticator app:'),
                  if (qrCodeUrl.isNotEmpty) Image.network(qrCodeUrl),
                  Text('Secret: $secret'),
                  TextField(
                    decoration: InputDecoration(labelText: 'Verification code'),
                    onChanged: (v) => token = v,
                  ),
                  const SizedBox(height: 16),
                  verifying
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _verify2FA,
                          child: Text('Verify and Enable'),
                        ),
                ] else ...[
                  Text('2FA is enabled'),
                  ElevatedButton(
                    onPressed: _disable2FA,
                    child: Text('Disable 2FA'),
                  ),
                ],
              ],
            ),
    );
  }
}

Future<String> getDumbFolder({bool media = false}) async {
  final dir = await getApplicationDocumentsDirectory();
  final dumbDir = Directory('${dir.path}/Dumb/${media ? 'Media' : 'Files'}');
  if (!await dumbDir.exists()) await dumbDir.create(recursive: true);
  return dumbDir.path;
}
