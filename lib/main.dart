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
import 'package:video_player/video_player.dart';
import 'package:mime/mime.dart';

void main() => runApp(const DumbApp());

const String apiUrl = 'http://localhost:3000/api';

class DumbApp extends StatelessWidget {
  const DumbApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'DUMB Messenger',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: AuthGate(),
    );
  }
}

// =================== AUTH ==========================
class AuthGate extends StatefulWidget {
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
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChannelsScreen(token: token!)));
        return;
      }
      prefs.remove('token');
    }
    setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return loading
        ? const Scaffold(body: Center(child: CircularProgressIndicator()))
        : AuthScreen(onLogin: (t) async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('token', t);
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChannelsScreen(token: t)));
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
    setState(() => loading = true);
    final url = isLogin ? '$apiUrl/login' : '$apiUrl/register';
    final resp = await http.post(Uri.parse(url), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'username': username, 'password': password, if (requires2FA) 'twoFactorToken': twoFactorToken}));
    final json = jsonDecode(resp.body);

    if (resp.statusCode != 200 || json['success'] != true) {
      if (json['requires2FA'] == true) {
        setState(() {
          requires2FA = true;
          sessionId = json['sessionId'] ?? '';
          error = json['message'] ?? 'Введите код 2FA';
        });
      } else {
        setState(() {
          error = json['error'] ?? 'Ошибка авторизации';
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
        error = 'Неизвестная ошибка';
        loading = false;
      });
    }
  }

  void _verify2FA() async {
    setState(() => loading = true);
    final resp = await http.post(Uri.parse('$apiUrl/2fa/verify-login'), headers: {'Content-Type': 'application/json'}, body: jsonEncode({'username': username, 'sessionId': sessionId, 'twoFactorToken': twoFactorToken}));
    final json = jsonDecode(resp.body);

    if (json['success'] == true && json['token'] != null) {
      widget.onLogin(json['token']);
    } else {
      setState(() {
        error = json['error'] ?? 'Ошибка 2FA';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(isLogin ? 'Вход' : 'Регистрация')),
      body: Center(
        child: SizedBox(
          width: 350,
          child: Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                TextField(
                  decoration: const InputDecoration(labelText: 'Имя пользователя'),
                  onChanged: (v) => username = v,
                  enabled: !loading,
                ),
                TextField(
                  decoration: const InputDecoration(labelText: 'Пароль'),
                  obscureText: true,
                  onChanged: (v) => password = v,
                  enabled: !loading,
                ),
                if (requires2FA)
                  TextField(
                    decoration: const InputDecoration(labelText: 'Код 2FA'),
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
                          child: Text(requires2FA ? 'Подтвердить 2FA' : isLogin ? 'Войти' : 'Зарегистрироваться'),
                        ),
                        TextButton(
                          onPressed: () => setState(() {
                            isLogin = !isLogin;
                            error = '';
                            requires2FA = false;
                          }),
                          child: Text(isLogin ? 'Регистрация' : 'Войти'),
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

// =============== CHANNELS ===================
class ChannelsScreen extends StatefulWidget {
  final String token;
  const ChannelsScreen({required this.token});
  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List channels = [];
  String error = '', search = '', channelName = '';
  bool loading = true, creating = false;

  @override
  void initState() {
    super.initState();
    _loadChannels();
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
        error = json['error'] ?? 'Ошибка загрузки каналов';
        loading = false;
      });
    }
  }

  Future<void> _createChannel() async {
    setState(() => creating = true);
    final resp = await http.post(Uri.parse('$apiUrl/channels/create'), headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'}, body: jsonEncode({'name': channelName}));
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      await _loadChannels();
      channelName = '';
    }
    setState(() {
      error = json['error'] ?? '';
      creating = false;
    });
  }

  Future<void> _searchChannels() async {
    setState(() => loading = true);
    final resp = await http.post(Uri.parse('$apiUrl/channels/search'), headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'}, body: jsonEncode({'query': search}));
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() {
        channels = json['channels'] ?? [];
        loading = false;
      });
    } else {
      setState(() {
        error = json['error'] ?? 'Ошибка поиска';
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Каналы'), actions: [
        IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SettingsScreen(token: widget.token)))),
      ]),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(labelText: 'Поиск каналов'),
                      onChanged: (v) => search = v,
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.search), onPressed: _searchChannels),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: Row(children: [
                  Expanded(
                    child: TextField(
                      decoration: const InputDecoration(labelText: 'Создать канал'),
                      onChanged: (v) => channelName = v,
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.add), onPressed: _createChannel),
                ]),
              ),
              if (error.isNotEmpty) Padding(padding: const EdgeInsets.all(8.0), child: Text(error, style: const TextStyle(color: Colors.red))),
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

// ================= CHAT ==========================
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

  @override
  void initState() {
    super.initState();
    _recorder = FlutterSoundRecorder();
    _recorder!.openRecorder();
    _loadMessages();
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return false;
      await _loadMessages();
      return true;
    });
  }

  @override
  void dispose() {
    _recorder?.closeRecorder();
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
      if (scrollController.hasClients) {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
      }
    } else {
      setState(() {
        error = json['error'] ?? 'Ошибка загрузки сообщений';
        loading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    setState(() => sending = true);
    final resp = await http.post(Uri.parse('$apiUrl/message'), headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'}, body: jsonEncode({'channel': widget.channel, 'text': text}));
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      text = '';
      await _loadMessages();
    } else {
      setState(() => error = json['error'] ?? 'Ошибка отправки');
    }
    setState(() => sending = false);
  }

  Future<void> _sendFile() async {
  final res = await FilePicker.platform.pickFiles();
  if (res == null || res.files.isEmpty) return;
  final pf = res.files.single;
  final mimeType = lookupMimeType(pf.name) ?? '';
  final isMedia = mimeType.startsWith('image/') || mimeType.startsWith('video/');
  final saveDir = await getDumbFolder(media: isMedia);

  // Создаём File из pf.path и копируем в нужную папку
  final sourceFile = File(pf.path!);
  final savedFile = await sourceFile.copy('$saveDir/${pf.name}');

  // Загружаем файл на сервер
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
    await _loadMessages();
  } else {
    setState(() => error = json['error'] ?? 'Ошибка загрузки файла');
  }
}

  Future<void> _startRecording() async {
    var status = await Permission.microphone.request();
    if (!status.isGranted) {
      setState(() => error = 'Нет разрешения на микрофон');
      return;
    }
    Directory tempDir = await getTemporaryDirectory();
    _voiceFilePath = '${tempDir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.aac';
    await _recorder!.startRecorder(toFile: _voiceFilePath, codec: Codec.aacADTS);
    setState(() => _isRecording = true);
  }

  Future<void> _stopRecordingAndSend() async {
    await _recorder!.stopRecorder();
    setState(() => _isRecording = false);
    if (_voiceFilePath == null) return;

    // 1. Запрос voiceId и uploadUrl
    final resp = await http.post(
      Uri.parse('$apiUrl/voice/upload'),
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
      body: jsonEncode({'channel': widget.channel, 'duration': 0}),
    );
    final jsonResp = jsonDecode(resp.body);
    if (jsonResp['success'] != true) {
      setState(() => error = jsonResp['error'] ?? 'Ошибка подготовки голосового');
      return;
    }
    final voiceId = jsonResp['voiceId'];
    final uploadUrl = 'http://localhost:3000${jsonResp['uploadUrl']}';

    // 2. Отправка файла
    var request = http.MultipartRequest('POST', Uri.parse(uploadUrl));
    request.headers['Authorization'] = 'Bearer ${widget.token}';
    request.files.add(await http.MultipartFile.fromPath('file', _voiceFilePath!));
    var uploadResp = await request.send();
    if (uploadResp.statusCode != 200) {
      setState(() => error = 'Ошибка загрузки голосового');
      return;
    }

    // 3. Отправка сообщения
    final msgResp = await http.post(
      Uri.parse('$apiUrl/message/voice-only'),
      headers: {'Authorization': 'Bearer ${widget.token}', 'Content-Type': 'application/json'},
      body: jsonEncode({'channel': widget.channel, 'voiceMessage': voiceId}),
    );
    final msgJson = jsonDecode(await msgResp.body);
    if (msgJson['success'] != true) {
      setState(() => error = msgJson['error'] ?? 'Ошибка отправки голосового');
      return;
    }

    await _loadMessages();
  }

  Future<void> _playVoice(String url) async {
    final player = AudioPlayer();
    await player.setUrl('http://localhost:3000$url');
    await player.play();
  }

  Future<void> _downloadFile(String url, String filename, String mimeType) async {
    final isMedia = mimeType.startsWith('image/') || mimeType.startsWith('video/');
    final folder = await getDumbFolder(media: isMedia);
    final resp = await http.get(Uri.parse('http://localhost:3000$url'));
    final file = File('$folder/$filename');
    await file.writeAsBytes(resp.bodyBytes);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Скачано: $filename')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Канал: ${widget.channel}')),
      body: loading
          ? const Center(child: CircularProgressIndicator())
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
                              child: Text('▶️ Голосовое (${msg['voice']['duration']?.toStringAsFixed(1) ?? ''} сек)', style: const TextStyle(color: Colors.blue)),
                            ),
                        ],
                      ),
                      subtitle: Text(msg['from'] ?? '', style: const TextStyle(fontSize: 12)),
                      dense: true,
                    );
                  },
                ),
              ),
              if (error.isNotEmpty) Padding(padding: const EdgeInsets.all(8.0), child: Text(error, style: const TextStyle(color: Colors.red))),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.attach_file),
                        onPressed: _sendFile,
                        tooltip: 'Отправить файл',
                      ),
                      IconButton(
                        icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                        onPressed: _isRecording ? _stopRecordingAndSend : _startRecording,
                        color: _isRecording ? Colors.red : Colors.blue,
                        tooltip: 'Голосовое',
                      ),
                      Expanded(
                        child: TextField(
                          decoration: const InputDecoration(
                            hintText: 'Сообщение...',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          ),
                          minLines: 1,
                          maxLines: 5,
                          onChanged: (v) => text = v,
                          controller: TextEditingController(text: text),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.send),
                        onPressed: _sendMessage,
                        tooltip: 'Отправить',
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
        onTap: () => _downloadFile(url, filename, mime),
        child: Image.network('http://localhost:3000$url', width: 150, height: 150, fit: BoxFit.cover),
      );
    } else if (mime.startsWith('video/')) {
      return GestureDetector(
        onTap: () => _downloadFile(url, filename, mime),
        child: Icon(Icons.videocam, size: 40),
        // Можно добавить превью видео через video_player
      );
    } else {
      return GestureDetector(
        onTap: () => _downloadFile(url, filename, mime),
        child: Text('📎 $filename', style: const TextStyle(color: Colors.blue)),
      );
    }
  }
}

// ================== FILE UTILS ==================
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

// ================= AVATARS ======================
class UserAvatar extends StatelessWidget {
  final String username, token;
  const UserAvatar({required this.username, required this.token});
  @override
  Widget build(BuildContext context) {
    final avatarUrl = 'http://localhost:3000/api/user/$username/avatar';
    return CircleAvatar(
      backgroundImage: NetworkImage(avatarUrl),
      child: Text(username.substring(0, 1)),
    );
  }
}

// =============== SETTINGS ======================
class SettingsScreen extends StatelessWidget {
  final String token;
  const SettingsScreen({required this.token});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Настройки')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Выйти'),
            leading: const Icon(Icons.logout),
            onTap: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('token');
              Navigator.of(context).popUntil((r) => r.isFirst);
            },
          ),
          // В будущем: управление 2FA, аватаром, паролем и т.д.
        ],
      ),
    );
  }
}
