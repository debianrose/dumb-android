import 'package:shared_preferences/shared_preferences.dart';

// Хранение токена
Future<void> storeToken(String token) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('auth_token', token);
}

Future<String?> getStoredToken() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('auth_token');
}

Future<void> clearStoredToken() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('auth_token');
}

// Хранение настроек сервера
Future<void> storeServerConfig(String ip, String port) async {
  final prefs = await SharedPreferences.getInstance();
  
  // Очищаем IP от http:// или https://
  String cleanIp = ip.replaceAll(RegExp(r'https?://'), '').trim();
  
  await prefs.setString('server_ip', cleanIp);
  await prefs.setString('server_port', port);
}

Future<Map<String, String>> getServerConfig() async {
  final prefs = await SharedPreferences.getInstance();
  String ip = prefs.getString('server_ip') ?? '10.0.2.2';
  String port = prefs.getString('server_port') ?? '3000';
  
  ip = ip.replaceAll(RegExp(r'https?://'), '').trim();
  
  return {
    'ip': ip,
    'port': port,
  };
}

// Утилиты
String formatTime(int timestamp) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

String formatDate(int timestamp) {
  final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${date.day}.${date.month}.${date.year}';
}
