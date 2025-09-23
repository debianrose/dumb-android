import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'channel_selection_screen.dart';
import 'two_fa_dialog.dart';

class AuthScreen extends StatefulWidget {
  @override
  _AuthScreenState createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _currentToken;
  String? _currentUser;

  Future<void> _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showError('Please enter username and password');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        _currentToken = result['token'];
        _currentUser = username;
        _proceedToChannelSelection();
      } else if (result['requires2FA'] == true) {
        final sessionId = result['sessionId'];
        _handle2FALogin(sessionId, username);
      } else {
        _showError(result['error'] ?? 'Login failed');
      }
    } catch (e) {
      _showError('Login failed: no response');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _handle2FALogin(String sessionId, String username) {
    showDialog(
      context: context,
      builder: (context) => TwoFADialog(
        sessionId: sessionId,
        username: username,
        onTokenEntered: (token) => _verify2FALogin(sessionId, username, token),
      ),
    );
  }

  Future<void> _verify2FALogin(String sessionId, String username, String token) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/2fa/verify-login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'sessionId': sessionId,
          'twoFactorToken': token,
        }),
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        _currentToken = result['token'];
        _currentUser = username;
        _proceedToChannelSelection();
      } else {
        _showError(result['error'] ?? '2FA verification failed');
      }
    } catch (e) {
      _showError('2FA verification failed');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _register() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      _showError('Please enter username and password');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        _showSuccess('Registration successful');
      } else {
        _showError(result['error'] ?? 'Registration failed');
      }
    } catch (e) {
      _showError('Registration failed');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _proceedToChannelSelection() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => ChannelSelectionScreen(
          token: _currentToken!,
          username: _currentUser!,
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
      appBar: AppBar(title: Text('Authentication')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 24),
            if (_isLoading)
              CircularProgressIndicator()
            else
              Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _login,
                      child: Text('Login'),
                    ),
                  ),
                  SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _register,
                      child: Text('Register'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
