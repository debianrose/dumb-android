import 'package:flutter/material.dart';
import 'api_client.dart';
import 'models.dart';

class AuthScreen extends StatefulWidget {
  final ApiClient apiClient;
  final Function(String, String) onLogin;
  final VoidCallback onConfigPressed;

  const AuthScreen({
    super.key,
    required this.apiClient,
    required this.onLogin,
    required this.onConfigPressed,
  });

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
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _validateInput() {
    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    if (username.isEmpty) {
      _showError('Введите имя пользователя');
      return false;
    }

    if (password.isEmpty) {
      _showError('Введите пароль');
      return false;
    }

    if (username.length < 3) {
      _showError('Имя пользователя должно быть не менее 3 символов');
      return false;
    }

    if (password.length < 6) {
      _showError('Пароль должен быть не менее 6 символов');
      return false;
    }

    final usernameRegex = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!usernameRegex.hasMatch(username)) {
      _showError('Имя пользователя может содержать только буквы, цифры и подчеркивания');
      return false;
    }

    return true;
  }

  Future<void> _handleAuth() async {
    if (!_validateInput()) return;

    setState(() => _isLoading = true);

    try {
      ApiResponse response;
      
      if (_isRegistering) {
        response = await widget.apiClient.register(
          _usernameController.text.trim(),
          _passwordController.text.trim(),
        );
      } else {
        response = await widget.apiClient.login(
          _usernameController.text.trim(),
          _passwordController.text.trim(),
          twoFactorToken: _show2FAField ? _twoFactorController.text : null,
        );
      }

      if (response.success) {
        if (_isRegistering) {
          _showSuccess('Регистрация успешна! Теперь войдите.');
          setState(() {
            _isRegistering = false;
            _passwordController.clear();
          });
        } else {
          if (response.data?['requires2FA'] == true) {
            setState(() {
              _show2FAField = true;
              _pendingUsername = _usernameController.text.trim();
              _pendingSessionId = response.data?['sessionId'];
            });
          } else {
            widget.onLogin(_usernameController.text.trim(), response.data?['token']);
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
      appBar: AppBar(
        title: const Text('Вход в чат'),
        backgroundColor: Colors.blue.shade800,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: widget.onConfigPressed,
            tooltip: 'Настройки сервера',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.white,
            ],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: Colors.blue.shade800,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _isRegistering ? 'Регистрация' : 'Вход в чат',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _usernameController,
                        decoration: InputDecoration(
                          labelText: 'Имя пользователя',
                          prefixIcon: const Icon(Icons.person),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          hintText: 'от 3 символов, только буквы/цифры',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          prefixIcon: const Icon(Icons.lock),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          hintText: _isRegistering ? 'не менее 6 символов' : '',
                        ),
                      ),
                      if (_show2FAField) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _twoFactorController,
                          decoration: InputDecoration(
                            labelText: 'Код 2FA',
                            prefixIcon: const Icon(Icons.security),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Введите код из приложения аутентификации',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      _isLoading
                          ? const CircularProgressIndicator()
                          : Column(
                              children: [
                                if (_show2FAField)
                                  ElevatedButton(
                                    onPressed: _verify2FA,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade800,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(double.infinity, 50),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: const Text('Подтвердить 2FA'),
                                  )
                                else
                                  ElevatedButton(
                                    onPressed: _handleAuth,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blue.shade800,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(double.infinity, 50),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    child: Text(_isRegistering ? 'Зарегистрироваться' : 'Войти'),
                                  ),
                                const SizedBox(height: 16),
                                TextButton(
                                  onPressed: _isLoading
                                      ? null
                                      : () {
                                          setState(() {
                                            _isRegistering = !_isRegistering;
                                            _show2FAField = false;
                                            _usernameController.clear();
                                            _passwordController.clear();
                                            _twoFactorController.clear();
                                          });
                                        },
                                  child: Text(
                                    _isRegistering
                                        ? 'Уже есть аккаунт? Войти'
                                        : 'Нет аккаунта? Зарегистрироваться',
                                    style: TextStyle(color: Colors.blue.shade800),
                                  ),
                                ),
                              ],
                            ),
                      const SizedBox(height: 16),
                      if (_isRegistering) 
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: const Text(
                            'Требования:\n• Имя пользователя: от 3 символов (только буквы, цифры, _)\n• Пароль: не менее 6 символов',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        Container(
                          padding: const EdgeInsets.all(8),
                          child: const Text(
                            'ТЕСТОВАЯ ВЕРСИЯ',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
