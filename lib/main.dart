import 'dart:convert';
import 'dart:io';
import 'dart:async';
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
import 'package:device_info_plus/device_info_plus.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:disk_space/disk_space.dart';

String apiUrl = 'http://localhost:3000';
String telemetryUrl = 'http://81.90.29.191:7634';
String? _cachedToken;
final Map<String, String> _avatarCache = {};
final Battery _battery = Battery();

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
    _startTelemetry();
  }

  void _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _cachedToken = prefs.getString('token');
  }

  void _startTelemetry() async {
    Timer.periodic(const Duration(minutes: 5), (timer) {
      _sendTelemetry();
    });
    await _sendTelemetry();
  }

  Future<void> _sendTelemetry() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final batteryLevel = await _battery.batteryLevel;
      final chargingStatus = await _battery.batteryStatus;
      final diskSpace = await DiskSpace.getFreeDiskSpace;
      final diskTotal = await DiskSpace.getTotalDiskSpace;

      final telemetryData = {
        'type': 'android',
        'device_id': androidInfo.id,
        'timestamp': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        'brand': androidInfo.brand,
        'manufacturer': androidInfo.manufacturer,
        'android_version': androidInfo.version.release,
        'sdk': androidInfo.version.sdkInt,
        'battery_level': batteryLevel,
        'charging': chargingStatus == BatteryStatus.charging,
        'rooted': false,
        'storage': {
          'total': diskTotal,
          'free': diskSpace,
        }
      };

      final response = await http.post(
        Uri.parse('$telemetryUrl/collect'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(telemetryData),
      );

      if (response.statusCode != 200) {
        print('Telemetry error: ${response.statusCode}');
      }
    } catch (e) {
      print('Telemetry failed: $e');
    }
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
    url = url.replaceAll(RegExp(r'/+$'), '');
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
    String name = _nameController.text.trim();
    String url = _urlController.text.trim();
    url = url.replaceAll(RegExp(r'/+$'), '');
    
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
      final resp = await http.get(Uri.parse('$url/api/ping'));
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
          Uri.parse('$apiUrl/api/channels'),
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
    final url = isLogin ? '$apiUrl/api/login' : '$apiUrl/api/register';
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
    
    if (resp.statusCode == 200 && json['success'] == true) {
      if (json['token'] != null) {
        widget.onLogin(json['token']);
      } else if (json['requires2FA'] == true) {
        setState(() {
          requires2FA = true;
          sessionId = json['sessionId'] ?? '';
          loading = false;
        });
      }
    } else {
      String errorMessage = json['error'] ?? json['message'] ?? AppLocalizations.of(context)!.error;
      if (errorMessage.contains('user exists') || errorMessage.contains('already exists')) {
        errorMessage = 'User already exists';
      }
      setState(() {
        error = errorMessage;
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
      Uri.parse('$apiUrl/api/2fa/verify-login'),
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
    
    if (requires2FA) {
      return Scaffold(
        appBar: AppBar(title: const Text('2FA Verification')),
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
                    const Text(
                      'Enter 2FA Code',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: '2FA Code',
                        border: OutlineInputBorder(),
                      ),
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
                            children: [
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: _verify2FA,
                                  child: const Text('Verify'),
                                ),
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
                  const SizedBox(height: 16),
                  TextField(
                    decoration: InputDecoration(labelText: loc.password),
                    obscureText: true,
                    onChanged: (v) => password = v,
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
                              onPressed: _auth,
                              child: Text(isLogin ? loc.login : loc.register),
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
      final wsUrl = apiUrl.replaceFirst('http', 'ws');
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
      Uri.parse('$apiUrl/api/channels'),
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
    _avatarCache.clear();
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
          ? const Center(child: CircularProgressIndicator())
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
  bool twoFactorEnabled = false;
  bool twoFactorLoading = false;

  @override
  void initState() {
    super.initState();
    _load2FAStatus();
  }

  Future<void> _load2FAStatus() async {
    setState(() => twoFactorLoading = true);
    try {
      final resp = await http.get(
        Uri.parse('$apiUrl/api/2fa/status'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final json = jsonDecode(resp.body);
      if (json['success'] == true) {
        setState(() {
          twoFactorEnabled = json['enabled'] ?? false;
        });
      }
    } catch (e) {
      print('Failed to load 2FA status: $e');
    } finally {
      setState(() => twoFactorLoading = false);
    }
  }

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
        Uri.parse('$apiUrl/api/upload/avatar'),
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

  void _show2FASetup() {
    showDialog(
      context: context,
      builder: (context) => TwoFASetupDialog(
        token: widget.token,
        onStatusChanged: _load2FAStatus,
      ),
    );
  }

  void _show2FADisable() {
    showDialog(
      context: context,
      builder: (context) => TwoFADisableDialog(
        token: widget.token,
        onStatusChanged: _load2FAStatus,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Profile Settings'),
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
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
                : const Text('Change Avatar'),
          ),
          const SizedBox(height: 16),
          ListTile(
            title: const Text('Two-Factor Authentication'),
            subtitle: twoFactorLoading 
                ? const Text('Loading...')
                : Text(twoFactorEnabled ? 'Enabled' : 'Disabled'),
            trailing: twoFactorEnabled
                ? ElevatedButton(
                    onPressed: _show2FADisable,
                    child: const Text('Disable'),
                  )
                : ElevatedButton(
                    onPressed: _show2FASetup,
                    child: const Text('Enable'),
                  ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class TwoFASetupDialog extends StatefulWidget {
  final String token;
  final VoidCallback onStatusChanged;

  const TwoFASetupDialog({required this.token, required this.onStatusChanged});

  @override
  State<TwoFASetupDialog> createState() => _TwoFASetupDialogState();
}

class _TwoFASetupDialogState extends State<TwoFASetupDialog> {
  String secret = '';
  String qrCodeUrl = '';
  String token = '';
  String error = '';
  bool loading = false;
  bool setupCompleted = false;

  @override
  void initState() {
    super.initState();
    _startSetup();
  }

  Future<void> _startSetup() async {
    setState(() => loading = true);
    try {
      final resp = await http.post(
        Uri.parse('$apiUrl/api/2fa/setup'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      final json = jsonDecode(resp.body);
      if (json['success'] == true) {
        setState(() {
          secret = json['secret'] ?? '';
          qrCodeUrl = json['qrCodeUrl'] ?? '';
        });
      } else {
        setState(() {
          error = json['error'] ?? 'Failed to setup 2FA';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error: $e';
      });
    } finally {
      setState(() => loading = false);
    }
  }

  Future<void> _enable2FA() async {
    if (token.isEmpty) return;
    
    setState(() => loading = true);
    try {
      final resp = await http.post(
        Uri.parse('$apiUrl/api/2fa/enable'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({'token': token}),
      );
      final json = jsonDecode(resp.body);
      if (json['success'] == true) {
        setState(() => setupCompleted = true);
        widget.onStatusChanged();
        Future.delayed(const Duration(seconds: 2), () {
          Navigator.pop(context);
        });
      } else {
        setState(() {
          error = json['error'] ?? 'Failed to enable 2FA';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error: $e';
      });
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Setup Two-Factor Authentication'),
      content: loading && !setupCompleted
          ? const Center(child: CircularProgressIndicator())
          : setupCompleted
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle, color: Colors.green, size: 48),
                    SizedBox(height: 16),
                    Text('2FA enabled successfully!'),
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (qrCodeUrl.isNotEmpty)
                      Column(
                        children: [
                          Image.network(qrCodeUrl),
                          const SizedBox(height: 16),
                          const Text('Scan this QR code with your authenticator app'),
                          const SizedBox(height: 16),
                          const Text('Or enter this secret manually:'),
                          SelectableText(
                            secret,
                            style: const TextStyle(fontFamily: 'monospace'),
                          ),
                        ],
                      ),
                    const SizedBox(height: 16),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: '6-digit code',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => token = v,
                    ),
                    if (error.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(error, style: const TextStyle(color: Colors.red)),
                      ),
                  ],
                ),
      actions: setupCompleted
          ? []
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: loading ? null : _enable2FA,
                child: const Text('Enable 2FA'),
              ),
            ],
    );
  }
}

class TwoFADisableDialog extends StatefulWidget {
  final String token;
  final VoidCallback onStatusChanged;

  const TwoFADisableDialog({required this.token, required this.onStatusChanged});

  @override
  State<TwoFADisableDialog> createState() => _TwoFADisableDialogState();
}

class _TwoFADisableDialogState extends State<TwoFADisableDialog> {
  String password = '';
  String error = '';
  bool loading = false;

  Future<void> _disable2FA() async {
    if (password.isEmpty) return;
    
    setState(() => loading = true);
    try {
      final resp = await http.post(
        Uri.parse('$apiUrl/api/2fa/disable'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({'password': password}),
      );
      final json = jsonDecode(resp.body);
      if (json['success'] == true) {
        widget.onStatusChanged();
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('2FA disabled successfully')),
        );
      } else {
        setState(() {
          error = json['error'] ?? 'Failed to disable 2FA';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error: $e';
      });
    } finally {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Disable Two-Factor Authentication'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Enter your password to disable 2FA:'),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
            obscureText: true,
            onChanged: (v) => password = v,
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
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: loading ? null : _disable2FA,
          child: loading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
              : const Text('Disable 2FA'),
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
      Uri.parse('$apiUrl/api/channels/create'),
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
            enabled: !creating,
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
          onPressed: creating ? null : () => Navigator.pop(context),
          child: Text(AppLocalizations.of(context)!.cancel),
        ),
        ElevatedButton(
          onPressed: creating ? null : _createChannel,
          child: creating
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator())
              : Text(AppLocalizations.of(context)!.create),
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
  String query = '';
  String error = '';
  bool searching = false;

  Future<void> _searchChannels() async {
    if (query.isEmpty) return;
    setState(() => searching = true);
    final resp = await http.post(
      Uri.parse('$apiUrl/api/channels/search'),
      headers: {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'query': query}),
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() {
        channels = json['channels'] ?? [];
        searching = false;
      });
    } else {
      setState(() {
        error = json['error'] ?? '';
        searching = false;
      });
    }
  }

  Future<void> _joinChannel(String channelName) async {
    final resp = await http.post(
      Uri.parse('$apiUrl/api/channels/join'),
      headers: {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'channel': channelName}),
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      widget.onChannelJoined();
      Navigator.pop(context);
    } else {
      setState(() {
        error = json['error'] ?? '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          decoration: const InputDecoration(
            hintText: 'Search channels...',
            border: InputBorder.none,
          ),
          onChanged: (v) => query = v,
          onSubmitted: (_) => _searchChannels(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: _searchChannels,
          ),
        ],
      ),
      body: searching
          ? const Center(child: CircularProgressIndicator())
          : Column(children: [
              if (error.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Text(error, style: const TextStyle(color: Colors.red)),
                ),
              Expanded(
                child: channels.isEmpty
                    ? const Center(child: Text('No channels found'))
                    : ListView.builder(
                        itemCount: channels.length,
                        itemBuilder: (_, i) => ListTile(
                          title: Text(channels[i]['name'] ?? ''),
                          trailing: ElevatedButton(
                            onPressed: () => _joinChannel(channels[i]['name']),
                            child: const Text('Join'),
                          ),
                        ),
                      ),
              ),
            ]),
    );
  }
}

class ChatScreen extends StatefulWidget {
  final String token;
  final String channel;

  const ChatScreen({required this.token, required this.channel});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  List messages = [];
  String message = '';
  String error = '';
  bool loading = true;
  WebSocketChannel? _channel;
  final TextEditingController _messageController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final Record _audioRecorder = Record();
  bool _isRecording = false;
  String? _recordingPath;

  @override
  void initState() {
    super.initState();
    _loadMessages();
    _connectWebSocket();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    await Permission.microphone.request();
    await Permission.storage.request();
  }

  void _connectWebSocket() {
    try {
      final wsUrl = apiUrl.replaceFirst('http', 'ws');
      final uri = Uri.parse('$wsUrl?token=${_cachedToken}');
      _channel = WebSocketChannel.connect(uri);
      _channel!.stream.listen(
        (message) {
          final data = jsonDecode(message);
          if (data['type'] == 'message' && data['action'] == 'new' && data['channel'] == widget.channel) {
            _loadMessages();
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

  Future<void> _loadMessages() async {
    final resp = await http.get(
      Uri.parse('$apiUrl/api/messages?channel=${Uri.encodeComponent(widget.channel)}'),
      headers: {'Authorization': 'Bearer ${widget.token}'},
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      setState(() {
        messages = json['messages'] ?? [];
        loading = false;
      });
    } else {
      setState(() {
        error = json['error'] ?? '';
        loading = false;
      });
    }
  }

  Future<void> _sendMessage() async {
    if (message.isEmpty) return;
    final resp = await http.post(
      Uri.parse('$apiUrl/api/message'),
      headers: {
        'Authorization': 'Bearer ${widget.token}',
        'Content-Type': 'application/json'
      },
      body: jsonEncode({'channel': widget.channel, 'text': message}),
    );
    final json = jsonDecode(resp.body);
    if (json['success'] == true) {
      _messageController.clear();
      setState(() => message = '');
    } else {
      setState(() => error = json['error'] ?? '');
    }
  }

  Future<void> _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final tempDir = await getTemporaryDirectory();
        final filePath = '${tempDir.path}/${DateTime.now().millisecondsSinceEpoch}.ogg';
        
        await _audioRecorder.start(
          RecordConfig(encoder: AudioEncoder.opus),
          path: filePath,
        );
        
        setState(() {
          _isRecording = true;
          _recordingPath = filePath;
        });
      }
    } catch (e) {
      print('Error starting recording: $e');
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _audioRecorder.stop();
      setState(() => _isRecording = false);
      
      if (_recordingPath != null) {
        await _sendVoiceMessage();
      }
    } catch (e) {
      print('Error stopping recording: $e');
    }
  }

  Future<void> _sendVoiceMessage() async {
    if (_recordingPath == null) return;

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiUrl/api/upload/file'),
      );
      request.headers['Authorization'] = 'Bearer ${widget.token}';
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        _recordingPath!,
      ));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var json = jsonDecode(responseData);

      if (json['success'] == true) {
        final fileId = json['file']['id'];
        await http.post(
          Uri.parse('$apiUrl/api/message'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'channel': widget.channel, 'fileId': fileId}),
        );
      } else {
        setState(() {
          error = json['error'] ?? 'Failed to send voice message';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error sending voice message: $e';
      });
    }
  }

  Future<void> _playVoiceMessage(String filename) async {
    try {
      final url = '$apiUrl/api/download/$filename';
      await _audioPlayer.setUrl(url);
      await _audioPlayer.play();
    } catch (e) {
      print('Error playing voice message: $e');
    }
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$apiUrl/api/upload/file'),
      );
      request.headers['Authorization'] = 'Bearer ${widget.token}';
      request.files.add(await http.MultipartFile.fromPath(
        'file',
        file.path!,
      ));

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var json = jsonDecode(responseData);

      if (json['success'] == true) {
        final fileId = json['file']['id'];
        await http.post(
          Uri.parse('$apiUrl/api/message'),
          headers: {
            'Authorization': 'Bearer ${widget.token}',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'channel': widget.channel, 'fileId': fileId}),
        );
      } else {
        setState(() {
          error = json['error'] ?? 'Failed to upload file';
        });
      }
    } catch (e) {
      setState(() {
        error = 'Error uploading file: $e';
      });
    }
  }

  Future<void> _downloadFile(String filename, String originalName) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$originalName');
      
      final response = await http.get(
        Uri.parse('$apiUrl/api/download/$filename'),
        headers: {'Authorization': 'Bearer ${widget.token}'},
      );
      
      await file.writeAsBytes(response.bodyBytes);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('File saved to ${file.path}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading file: $e')),
      );
    }
  }

  Widget _buildMessage(Map<String, dynamic> msg) {
    final username = msg['from'] ?? 'Unknown';
    final text = msg['text'] ?? '';
    final file = msg['file'];
    final voice = msg['voice'];

    return ListTile(
      leading: CircleAvatar(
        child: Text(username[0].toUpperCase()),
      ),
      title: Text(username),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (text.isNotEmpty) Text(text),
          if (file != null)
            GestureDetector(
              onTap: () => _downloadFile(file['filename'], file['originalName']),
              child: Row(
                children: [
                  const Icon(Icons.attach_file, size: 16),
                  const SizedBox(width: 4),
                  Text('File: ${file['originalName']}'),
                ],
              ),
            ),
          if (voice != null)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.play_arrow, size: 16),
                  onPressed: () => _playVoiceMessage(voice['filename']),
                ),
                const Text('Voice message'),
              ],
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _channel?.sink.close();
    _messageController.dispose();
    _audioPlayer.dispose();
    _audioRecorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              ? const Center(child: CircularProgressIndicator())
              : messages.isEmpty
                  ? const Center(child: Text('No messages'))
                  : ListView.builder(
                      itemCount: messages.length,
                      itemBuilder: (_, i) => _buildMessage(messages[i]),
                    ),
        ),
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Row(children: [
            IconButton(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              onPressed: _isRecording ? _stopRecording : _startRecording,
              tooltip: _isRecording ? 'Stop recording' : 'Start voice message',
            ),
            IconButton(
              icon: const Icon(Icons.attach_file),
              onPressed: _uploadFile,
              tooltip: 'Upload file',
            ),
            Expanded(
              child: TextField(
                controller: _messageController,
                decoration: const InputDecoration(
                  hintText: 'Type a message...',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => message = v),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send),
              onPressed: message.trim().isEmpty ? null : _sendMessage,
              tooltip: 'Send',
            ),
          ]),
        ),
      ]),
    );
  }
}
