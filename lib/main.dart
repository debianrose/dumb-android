import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:just_audio/just_audio.dart';
import 'package:mime/mime.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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
    if (token != null) {
      final resp = await http.get(Uri.parse('$apiUrl/channels'), headers: {'Authorization': 'Bearer $token!'});
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
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
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
  FlutterSoundRecorder? _recorder;
  bool _isRecording = false;
  String? _voiceFilePath;
  WebSocketChannel? _wsChannel;

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _recorder!.openRecorder();
    _loadMessages();
    _connectWebSocket();
  }

  void _connectWebSocket() {
    try {
      final wsUrl = apiUrl.replaceFirst('http', 'ws').replaceFirst('/api', '');
      _wsChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
      _wsChannel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'message' && data['action'] == 'new' && data['channel'] == widget.channel) {
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
    _recorder?.closeRecorder();
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
      setState(() {
        messages = json['messages'] ?? [];
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
    var status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() => error = AppLocalizations.of(context)?.error ?? 'No mic permission');
      return;
    }
    Directory tempDir = await getTemporaryDirectory();
    _voiceFilePath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.ogg';
    await _recorder!.startRecorder(toFile: _voiceFilePath, codec: Codec.opusOGG);
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecordingAndSend() async {
    await _recorder!.stopRecorder();
    setState(() => _isRecording = false);
    if (_voiceFilePath == null) return;

    final resp = await http.post(
      Uri.parse('$apiUrl/voice/upload'),
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
      body: jsonEncode({'channel': widget.channel, 'duration': 0}),
    );
    final jsonResp = jsonDecode(resp.body);
    
    if (jsonResp['success'] != true) {
      setState(() => error = jsonResp['error'] ?? AppLocalizations.of(context)?.error ?? 'Voice upload error');
      return;
    }
    
    final voiceId = jsonResp['voiceId'];
    final uploadUrl = apiUrl.replaceFirst('/api', '') + jsonResp['uploadUrl'];

    var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    request.headers['Authorization'] = 'Bearer ${widget.token}';
    request.files.add(await http.MultipartFile.fromPath('file', _voiceFilePath!));
    var uploadResp = await request.send();
    
    if (uploadResp.statusCode != 200) {
      setState(() => error = AppLocalizations.of(context)?.error ?? 'Voice upload error');
      return;
    }

    final msgResp = await http.post(
      Uri.parse('$apiUrl/message/voice-only'),
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
      body: jsonEncode({'channel': widget.channel, 'voiceMessage': voiceId}),
    );
    final msgJson = jsonDecode(await msgResp.body);    
    if (msgJson['success'] != true) {
      setState(() => error = msgJson['error'] ?? AppLocalizations.of(context)?.error ?? 'Voice send error');
    }
  }

  Future<void> _playVoice(String url) async {
    final player = AudioPlayer();
    await player.setUrl(apiUrl.replaceFirst('/api', '') + url);
    await player.play();
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

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text('${loc.channels}: ${widget.channel}')),
      body: loading
          ? Center(child: Text(loc.loading))
          : Column(children: [
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    return ListTile(
                      leading: msg['from'] != null ? UserAvatar(username: msg['from'], token: widget.token) : null,
                      title: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (msg['text'] != null && msg['text'].isNotEmpty)
                            Text(msg['text'] ?? ''),
                          if (msg['file'] != null)
                            _buildMessageFile(msg['file']),
                          if (msg['voice'] != null)
                            GestureDetector(
                              onTap: () => _playVoice(msg['voice']['downloadUrl']),
                              child: Text('▶️ ${loc.sendMessage} (${msg['voice']['duration']?.toStringAsFixed(1) ?? ''} сек)', style: const TextStyle(color: Colors.blue)),
                            ),
                        ],
                      ),
                      subtitle: Text(msg['from'] ?? '', style: const TextStyle(fontSize: 12)),
                      dense: true,
                    );
                  },
                ),
              ),
              if (error.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Text(error, style: const TextStyle(color: Colors.red))),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.attach_file),
                        onPressed: _sendFile,
                        tooltip: loc.sendMessage,
                      ),
                      IconButton(
                        icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                        onPressed: _isRecording ? _stopRecordingAndSend : _startRecording,
                        color: _isRecording ? Colors.red : Colors.blue,
                        tooltip: 'Voice',
                      ),
                      Expanded(
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: loc.typeMessage,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          minLines: 1,
                          maxLines: 5,
                          onChanged: (v) => text = v,
                          controller: TextEditingController(text: text),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: sending ? null : _sendMessage,
                        tooltip: loc.sendMessage,
                      ),
                    ],
                  ),
                ),
              ),
            ]),
    );
  }

  Widget _buildMessageFile(Map file) {
    final mime = file['mimetype'] ?? '';
    final url = file['downloadUrl'];
    final filename = file['originalName'] ?? 'file';
    
    if (mime.startsWith('image/')) {
      return GestureDetector(
        onTap: () => _viewImage(url, filename),
        child: Image.network(apiUrl.replaceFirst('/api', '') + url, width: 150, height: 150, fit: BoxFit.cover),
      );
    } else if (mime.startsWith('video/')) {
      return GestureDetector(
        onTap: () => _downloadFile(url, filename, mime),
        child: Icon(Icons.videocam, size: 40),
      );
    } else {
      return GestureDetector(
        onTap: () => _downloadFile(url, filename, mime),
        child: Text('📎 $filename', style: const TextStyle(color: Colors.blue)),
      );
    }
  }

  Future<void> _downloadFile(String url, String filename, String mimeType) async {
    final isMedia = mimeType.startsWith('image/') || mimeType.startsWith('video/');
    final folder = await getDumbFolder(media: isMedia);
    final resp = await http.get(Uri.parse(apiUrl.replaceFirst('/api', '') + url));
    final file = File('$folder/$filename');
    await file.writeAsBytes(resp.bodyBytes);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloaded: $filename')));
  }
}

Future<String> getDumbFolder({bool media = false}) async {
  Directory dir;
  if (Platform.isAndroid) {
    if (media) {
      dir = Directory('/storage/emulated/0/DCIM/DUMB');
    } else {
      dir = Directory('/storage/emulated/0/Documents/DUMB');
    }
  } else {
    dir = await getApplicationDocumentsDirectory();
  }
  if (!await dir.exists()) await dir.create(recursive: true);
  return dir.path;
}

class UserAvatar extends StatelessWidget {
  final String username, token;
  const UserAvatar({required this.username, required this.token});
  @override
  Widget build(BuildContext context) {
    final avatarUrl = '$apiUrl/user/$username/avatar?${DateTime.now().millisecondsSinceEpoch}';
    return CircleAvatar(
      backgroundImage: NetworkImage(avatarUrl),
      onBackgroundImageError: (exception, stackTrace) {},
      child: null,
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
  String? avatarUrl;
  bool uploadingAvatar = false;
  bool twoFAEnabled = false;
  bool loading2FA = true;
  String? twoFASecret;
  String? qrCodeUrl;
  String? twoFAError;
  Locale? tempLocale;
  String? username;
  String serverUrl = '';

@override
void initState() {
  super.initState();
  _loadUsernameAndInit();
  _loadServerUrl();
}

Future<void> _loadServerUrl() async {
  final prefs = await SharedPreferences.getInstance();
  setState(() {
    serverUrl = prefs.getString('server_url') ?? 'http://localhost:3000';
  });
}

Future<void> _loadUsernameAndInit() async {
  final prefs = await SharedPreferences.getInstance();
  setState(() {
    username = prefs.getString('username');
  });
  _loadAvatar();
  _load2FAStatus();
}

Future<void> _loadAvatar() async {
  if (username == null) return;
  setState(() {
    avatarUrl = '$apiUrl/user/$username/avatar?${DateTime.now().millisecondsSinceEpoch}';
  });
}

  Future<void> _pickAvatar() async {
    final res = await FilePicker.platform.pickFiles(type: FileType.image);
    if (res == null || res.files.isEmpty) return;
    setState(() => uploadingAvatar = true);
    final pf = res.files.single;
    final file = File(pf.path!);
    var req = http.MultipartRequest('POST', Uri.parse('$apiUrl/upload/avatar'));
    req.headers['Authorization'] = 'Bearer ${widget.token}';
    req.files.add(await http.MultipartFile.fromPath('avatar', file.path));
    var resp = await req.send();
    var json = jsonDecode(await resp.stream.bytesToString());
    setState(() {
      uploadingAvatar = false;
      if (json['success'] == true) {
        _loadAvatar();
      }
    });
  }

  Future<void> _load2FAStatus() async {
    setState(() => loading2FA = true);
    final resp = await http.get(Uri.parse('$apiUrl/2fa/status'), headers: {'Authorization': 'Bearer ${widget.token}'});
    final json = jsonDecode(resp.body);
    setState(() {
      twoFAEnabled = json['enabled'] == true;
      loading2FA = false;
    });
  }

  Future<void> _setup2FA() async {
    setState(() {
      loading2FA = true;
      twoFAError = null;
    });
    final resp = await http.post(Uri.parse('$apiUrl/2fa/setup'), headers: {'Authorization': 'Bearer ${widget.token}'});
    final json = jsonDecode(resp.body);
    setState(() {
      twoFASecret = json['secret'];
      qrCodeUrl = json['qrCodeUrl'];
      loading2FA = false;
    });
  }

  Future<void> _enable2FA(String code) async {
    setState(() => loading2FA = true);
    final resp = await http.post(
      Uri.parse('$apiUrl/2fa/enable'),
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
      body: jsonEncode({'token': code}),
    );
    final json = jsonDecode(resp.body);
    setState(() {
      loading2FA = false;
      if (json['success'] == true) {
        twoFAEnabled = true;
        twoFASecret = null;
        qrCodeUrl = null;
      } else {
        twoFAError = json['error'] ?? 'Ошибка 2FA';
      }
    });
  }

  Future<void> _disable2FA(String password) async {
    setState(() => loading2FA = true);
    final resp = await http.post(
      Uri.parse('$apiUrl/2fa/disable'),
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
      body: jsonEncode({'password': password}),
    );
    final json = jsonDecode(resp.body);
    setState(() {
      loading2FA = false;
      if (json['success'] == true) {
        twoFAEnabled = false;
      } else {
        twoFAError = json['error'] ?? 'Ошибка';
      }
    });
  }

  void _updateServerUrl(String url) {
    widget.setServerUrl(url);
    setState(() {
      serverUrl = url;
      apiUrl = '$url/api';
    });
    _loadAvatar();
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(title: Text(loc.settings)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            title: Text(loc.profile),
            leading: avatarUrl != null
                ? CircleAvatar(
                    backgroundImage: NetworkImage(avatarUrl!),
                    onBackgroundImageError: (exception, stackTrace) {},
                    child: null,
                  )
                : const CircleAvatar(child: Icon(Icons.person)),
            trailing: uploadingAvatar
                ? const CircularProgressIndicator()
                : IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: _pickAvatar,
                  ),
          ),
          const Divider(),
          ListTile(
            title: Text('Server URL'),
            subtitle: Text(serverUrl),
            trailing: IconButton(
              icon: Icon(Icons.edit),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    String newUrl = serverUrl;
                    return AlertDialog(
                      title: Text('Server URL'),
                      content: TextField(
                        decoration: InputDecoration(hintText: 'http://localhost:3000'),
                        onChanged: (v) => newUrl = v,
                        controller: TextEditingController(text: serverUrl),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: Text(loc.cancel),
                        ),
                        ElevatedButton(
                          onPressed: () {
                            _updateServerUrl(newUrl);
                            Navigator.pop(context);
                          },
                          child: Text('Save'),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          const Divider(),
          ListTile(
            title: Text('2FA'),
            subtitle: loading2FA
                ? const LinearProgressIndicator()
                : Text(twoFAEnabled ? loc.success : loc.error),
            trailing: twoFAEnabled
                ? IconButton(
                    icon: const Icon(Icons.lock_open),
                    onPressed: () {
                      showDialog(
                        context: context,
                        builder: (_) {
                          String pwd = "";
                          return AlertDialog(
                            title: Text(loc.confirm),
                            content: TextField(
                              obscureText: true,
                              decoration: InputDecoration(labelText: loc.password),
                              onChanged: (v) => pwd = v,
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(loc.cancel),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  _disable2FA(pwd);
                                  Navigator.pop(context);
                                },
                                child: Text(loc.confirm),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  )
                : IconButton(
                    icon: const Icon(Icons.lock),
                    onPressed: () async {
                      await _setup2FA();
                      showDialog(
                        context: context,
                        builder: (_) {
                          String code = "";
                          return AlertDialog(
                            title: Text("2FA"),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (qrCodeUrl != null)
                                  Image.memory(base64Decode(qrCodeUrl!.split(',').last)),
                                if (twoFASecret != null)
                                  SelectableText(twoFASecret!),
                                TextField(
                                  decoration: const InputDecoration(labelText: "2FA Code"),
                                  onChanged: (v) => code = v,
                                ),
                                if (twoFAError != null)
                                  Text(twoFAError!, style: const TextStyle(color: Colors.red)),
                              ],
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: Text(loc.cancel),
                              ),
                              ElevatedButton(
                                onPressed: () {
                                  _enable2FA(code);
                                  Navigator.pop(context);
                                },
                                child: Text(loc.confirm),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.language),
            title: Text(loc.language),
            trailing: DropdownButton<Locale>(
              value: tempLocale ?? Localizations.localeOf(context),
              items: const [
                DropdownMenuItem(child: Text("English"), value: Locale('en')),
                DropdownMenuItem(child: Text("Русский"), value: Locale('ru')),
              ],
              onChanged: (Locale? v) {
                if (v != null) {
                  setState(() => tempLocale = v);
                  widget.setLocale(v);
                }
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.brightness_6),
            title: Text(loc.settings),
            trailing: DropdownButton<ThemeMode>(
              value: widget.themeMode,
              items: const [
                DropdownMenuItem(child: Text("System"), value: ThemeMode.system),
                DropdownMenuItem(child: Text("Light"), value: ThemeMode.light),
                DropdownMenuItem(child: Text("Dark"), value: ThemeMode.dark),
              ],
              onChanged: (ThemeMode? v) {
                if (v != null) widget.setTheme(v);
              },
            ),
          ),
          ListTile(
            title: Text(loc.logout),
            leading: const Icon(Icons.logout),
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
        ],
      ),
    );
  }
}

