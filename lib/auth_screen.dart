import 'package:flutter/material.dart';
import 'api_client.dart';
import 'models.dart';
import 'l10n/app_localizations.dart';

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
        backgroundColor: Theme.of(context).colorScheme.error,
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
      _showError('Please enter username');
      return false;
    }

    if (password.isEmpty) {
      _showError('Please enter password');
      return false;
    }

    if (username.length < 3) {
      _showError('Username must be at least 3 characters');
      return false;
    }

    if (password.length < 6) {
      _showError('Password must be at least 6 characters');
      return false;
    }

    final usernameRegex = RegExp(r'^[a-zA-Z0-9_]+$');
    if (!usernameRegex.hasMatch(username)) {
      _showError('Username can only contain letters, numbers and underscores');
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
          _showSuccess('Registration successful! Please login.');
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
            final token = response.data?['token'] ?? '';
            widget.onLogin(_usernameController.text.trim(), token);
          }
        }
      } else {
        _showError(response.error ?? 'Authentication error');
      }
    } catch (e) {
      _showError('Connection error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _verify2FA() async {
    if (_twoFactorController.text.isEmpty) {
      _showError('Please enter 2FA code');
      return;
    }

    if (_pendingUsername == null || _pendingSessionId == null) {
      _showError('Session expired. Please try again.');
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
        final token = response.data?['token'] ?? '';
        widget.onLogin(_pendingUsername!, token);
      } else {
        _showError(response.error ?? '2FA verification failed');
      }
    } catch (e) {
      _showError('Connection error: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc?.appTitle ?? 'DUMB Android'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: widget.onConfigPressed,
            tooltip: loc?.settings ?? 'Settings',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 64,
                  color: colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  _isRegistering ? 'Register' : 'Login',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 32),
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: loc?.username ?? 'Username',
                    prefixIcon: const Icon(Icons.person_outline),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: loc?.password ?? 'Password',
                    prefixIcon: const Icon(Icons.lock_outline),
                  ),
                ),
                if (_show2FAField) ...[
                  const SizedBox(height: 16),
                  TextField(
                    controller: _twoFactorController,
                    decoration: const InputDecoration(
                      labelText: '2FA Code',
                      prefixIcon: Icon(Icons.security),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
                const SizedBox(height: 24),
                _isLoading
                    ? const CircularProgressIndicator()
                    : Column(
                        children: [
                          if (_show2FAField)
                            FilledButton(
                              onPressed: _verify2FA,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              child: const Text('Verify'),
                            )
                          else
                            FilledButton(
                              onPressed: _handleAuth,
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(double.infinity, 50),
                              ),
                              child: Text(_isRegistering ? 'Register' : 'Login'),
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
                                  ? 'Already have an account? Login'
                                  : 'No account? Register',
                            ),
                          ),
                        ],
                      ),
                const SizedBox(height: 24),
                if (_isRegistering) 
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceVariant,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Requirements:\n• Username: 3+ characters (a-z, 0-9, _)\n• Password: 6+ characters',
                      style: TextStyle(fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
