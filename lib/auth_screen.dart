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

  // 2FA настройка
  bool _show2FASetup = false;
  String? _twoFASecret;
  final _setup2FAController = TextEditingController();

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
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
          _showSuccess('Регистрация успешна! Теперь войдите.');
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

  Future<void> _setup2FA() async {
    setState(() => _isLoading = true);

    try {
      final response = await widget.apiClient.setup2FA();
      if (response.success) {
        setState(() {
          _show2FASetup = true;
          _twoFASecret = response.data?['secret'];
        });
        _showSuccess('2FA настройка начата. Сохраните секретный ключ!');
      } else {
        _showError(response.error ?? 'Ошибка настройки 2FA');
      }
    } catch (e) {
      _showError('Ошибка: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _enable2FA() async {
    if (_setup2FAController.text.isEmpty) {
      _showError('Введите код из приложения аутентификации');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await widget.apiClient.enable2FA(_setup2FAController.text);
      if (response.success) {
        setState(() {
          _show2FASetup = false;
          _twoFASecret = null;
        });
        _showSuccess('2FA успешно включена!');
      } else {
        _showError(response.error ?? 'Ошибка включения 2FA');
      }
    } catch (e) {
      _showError('Ошибка: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _build2FASetupDialog() {
    return AlertDialog(
      title: const Text('Настройка 2FA'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('1. Установите приложение аутентификации (Google Authenticator, Authy и т.д.)'),
            const SizedBox(height: 10),
            const Text('2. Добавьте новый аккаунт вручную:'),
            const SizedBox(height: 5),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: SelectableText(
                  _twoFASecret ?? '',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 10),
            const Text('3. Введите код из приложения:'),
            TextField(
              controller: _setup2FAController,
              decoration: const InputDecoration(
                labelText: 'Код подтверждения',
                hintText: '123456',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => setState(() {
            _show2FASetup = false;
            _twoFASecret = null;
          }),
          child: const Text('Отмена'),
        ),
        ElevatedButton(
          onPressed: _enable2FA,
          child: const Text('Включить 2FA'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Чат'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: widget.onConfigPressed,
            tooltip: 'Настройки сервера',
          ),
        ],
      ),
      body: Stack(
        children: [
          Padding(
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
                  decoration: const InputDecoration(
                    labelText: 'Имя пользователя',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Пароль',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_show2FAField) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _twoFactorController,
                    decoration: const InputDecoration(
                      labelText: 'Код 2FA',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
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
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              child: const Text('Подтвердить 2FA'),
                            )
                          else
                            ElevatedButton(
                              onPressed: _handleAuth,
                              style: ElevatedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              child: Text(_isRegistering ? 'Зарегистрироваться' : 'Войти'),
                            ),
                          const SizedBox(height: 10),
                          if (!_isRegistering && !_show2FAField)
                            OutlinedButton(
                              onPressed: _setup2FA,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              child: const Text('Настроить 2FA'),
                            ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: _isLoading
                                ? null
                                : () {
                                    setState(() {
                                      _isRegistering = !_isRegistering;
                                      _show2FAField = false;
                                      _show2FASetup = false;
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
          if (_show2FASetup) _build2FASetupDialog(),
        ],
      ),
    );
  }
}
