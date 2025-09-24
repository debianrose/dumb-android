import 'package:flutter/material.dart';
import 'api_client.dart';
import 'models.dart';

class AuthScreen extends StatefulWidget {
  final ApiClient apiClient;
  final Function(String, String) onLogin;

  const AuthScreen({super.key, required this.apiClient, required this.onLogin});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> with SingleTickerProviderStateMixin {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _twoFactorController = TextEditingController();
  
  bool _isLoading = false;
  bool _isRegistering = false;
  bool _show2FAField = false;
  String? _pendingUsername;
  String? _pendingSessionId;

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  Future<void> _handleAuth() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      _showError('Заполните все поля');
      return;
    }

    setState(() => _isLoading = true);

    try {
      ApiResponse response;
      
      if (_isRegistering) {
        response = await widget.apiClient.register(
          _usernameController.text,
          _passwordController.text,
        );
      } else {
        response = await widget.apiClient.login(
          _usernameController.text,
          _passwordController.text,
          twoFactorToken: _show2FAField ? _twoFactorController.text : null,
        );
      }

      if (response.success) {
        if (_isRegistering) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Регистрация успешна! Теперь войдите.')),
          );
          setState(() => _isRegistering = false);
        } else {
          if (response.data?['requires2FA'] == true) {
            setState(() {
              _show2FAField = true;
              _pendingUsername = _usernameController.text;
              _pendingSessionId = response.data?['sessionId'];
            });
          } else {
            widget.onLogin(_usernameController.text, response.data?['token']);
          }
        }
      } else {
        _showError(response.error ?? 'Ошибка авторизации');
      }
    } catch (e) {
      _showError('Ошибка соединения: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verify2FA() async {
    if (_twoFactorController.text.isEmpty) {
      _showError('Введите код 2FA');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await widget.apiClient.verify2FALogin(
        _pendingUsername!,
        _pendingSessionId!,
        _twoFactorController.text,
      );

      if (response.success) {
        widget.onLogin(_pendingUsername!, response.data?['token']);
      } else {
        _showError(response.error ?? 'Ошибка верификации 2FA');
      }
    } catch (e) {
      _showError('Ошибка соединения: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Чат')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _isRegistering ? 'Регистрация' : 'Вход',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(labelText: 'Имя пользователя'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Пароль'),
            ),
            if (_show2FAField) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _twoFactorController,
                decoration: const InputDecoration(labelText: 'Код 2FA'),
              ),
            ],
            const SizedBox(height: 20),
            _isLoading
                ? const CircularProgressIndicator()
                : Column(
                    children: [
                      if (_show2FAField)
                        ElevatedButton(
                          onPressed: _verify2FA,
                          child: const Text('Подтвердить 2FA'),
                        )
                      else
                        ElevatedButton(
                          onPressed: _handleAuth,
                          child: Text(_isRegistering ? 'Зарегистрироваться' : 'Войти'),
                        ),
                      TextButton(
                        onPressed: _isLoading
                            ? null
                            : () {
                                setState(() {
                                  _isRegistering = !_isRegistering;
                                  _show2FAField = false;
                                });
                              },
                        child: Text(_isRegistering
                            ? 'Уже есть аккаунт? Войти'
                            : 'Нет аккаунта? Зарегистрироваться'),
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}
