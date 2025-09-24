import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'utils.dart';

class ApiClient {
  String _baseUrl = 'http://10.0.2.2:3000';
  String? _token;

  Future<void> setServerConfig(String ip, String port) async {
    String cleanIp = ip.replaceAll(RegExp(r'https?://'), '').trim();
    _baseUrl = 'http://$cleanIp:$port';
    await storeServerConfig(cleanIp, port);
  }

  Future<void> loadServerConfig() async {
    final config = await getServerConfig();
    _baseUrl = 'http://${config['ip']}:${config['port']}';
  }

  void setToken(String token) {
    _token = token;
  }

  Future<Map<String, String>> _getHeaders() async {
    final headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    
    if (_token != null) {
      headers['Authorization'] = 'Bearer $_token';
    }
    
    return headers;
  }

  Future<ApiResponse> _handleResponse(http.Response response) async {
    if (response.statusCode == 200) {
      try {
        final data = json.decode(response.body);
        return ApiResponse(success: data['success'] ?? false, data: data);
      } catch (e) {
        return ApiResponse(success: false, error: 'Invalid JSON response');
      }
    } else if (response.statusCode == 401) {
      return ApiResponse(success: false, error: 'Authentication required');
    } else {
      return ApiResponse(success: false, error: 'HTTP ${response.statusCode}');
    }
  }

  Future<String?> validateToken(String token) async {
    _token = token;
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/users'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 10));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['success'] == true ? 'user' : null;
      }
      return null;
    } catch (e) {
      print('Token validation error: $e');
      return null;
    }
  }

  Future<ApiResponse> register(String username, String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/register'),
        headers: await _getHeaders(),
        body: json.encode({'username': username, 'password': password}),
      ).timeout(const Duration(seconds: 10));
      
      return await _handleResponse(response);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> login(String username, String password, {String? twoFactorToken}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/login'),
        headers: await _getHeaders(),
        body: json.encode({
          'username': username,
          'password': password,
          if (twoFactorToken != null) 'twoFactorToken': twoFactorToken,
        }),
      ).timeout(const Duration(seconds: 10));
      
      final result = await _handleResponse(response);
      if (result.success && result.data?['token'] != null) {
        _token = result.data?['token'];
        await storeToken(_token!);
      }
      return result;
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> verify2FALogin(String username, String sessionId, String twoFactorToken) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/2fa/verify-login'),
        headers: await _getHeaders(),
        body: json.encode({
          'username': username,
          'sessionId': sessionId,
          'twoFactorToken': twoFactorToken,
        }),
      ).timeout(const Duration(seconds: 10));
      
      final result = await _handleResponse(response);
      if (result.success && result.data?['token'] != null) {
        _token = result.data?['token'];
        await storeToken(_token!);
      }
      return result;
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> setup2FA() async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/2fa/setup'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 10));
      
      return await _handleResponse(response);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> enable2FA(String token) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/2fa/enable'),
        headers: await _getHeaders(),
        body: json.encode({'token': token}),
      ).timeout(const Duration(seconds: 10));
      
      return await _handleResponse(response);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> get2FAStatus() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/2fa/status'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 10));
      
      return await _handleResponse(response);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> disable2FA(String password) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/2fa/disable'),
        headers: await _getHeaders(),
        body: json.encode({'password': password}),
      ).timeout(const Duration(seconds: 10));
      
      return await _handleResponse(response);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> createChannel(String name) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/channels/create'),
        headers: await _getHeaders(),
        body: json.encode({'name': name}),
      ).timeout(const Duration(seconds: 10));
      
      return await _handleResponse(response);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> getChannels() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/channels'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 10));
      
      print('Channels response: ${response.statusCode} - ${response.body}');
      
      return await _handleResponse(response);
    } catch (e) {
      print('Channels error: $e');
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> joinChannel(String channel) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/channels/join'),
        headers: await _getHeaders(),
        body: json.encode({'channel': channel}),
      ).timeout(const Duration(seconds: 10));
      
      return await _handleResponse(response);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> leaveChannel(String channel) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/channels/leave'),
        headers: await _getHeaders(),
        body: json.encode({'channel': channel}),
      ).timeout(const Duration(seconds: 10));
      
      return await _handleResponse(response);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> getMessages(String channel, {int limit = 50, String? before}) async {
    try {
      final params = {'channel': channel, 'limit': limit.toString()};
      if (before != null) params['before'] = before;
      
      final response = await http.get(
        Uri.parse('$_baseUrl/api/messages').replace(queryParameters: params),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 10));
      
      return await _handleResponse(response);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> sendMessage(String channel, String text, {String? replyTo, String? fileId}) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/api/message'),
        headers: await _getHeaders(),
        body: json.encode({
          'channel': channel,
          'text': text,
          if (replyTo != null) 'replyTo': replyTo,
          if (fileId != null) 'fileId': fileId,
        }),
      ).timeout(const Duration(seconds: 10));
      
      return await _handleResponse(response);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  Future<ApiResponse> getUsers() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/api/users'),
        headers: await _getHeaders(),
      ).timeout(const Duration(seconds: 10));
      
      return await _handleResponse(response);
    } catch (e) {
      return ApiResponse(success: false, error: 'Connection error: $e');
    }
  }

  void logout() {
    _token = null;
    clearStoredToken();
  }

  String getCurrentUrl() {
    return _baseUrl;
  }
}
