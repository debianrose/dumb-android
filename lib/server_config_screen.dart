import 'package:flutter/material.dart';
import 'api_client.dart';
import 'utils.dart';

class ServerConfigScreen extends StatefulWidget {
  final ApiClient apiClient;
  final Function() onConfigSaved;

  const ServerConfigScreen({
    super.key,
    required this.apiClient,
    required this.onConfigSaved,
  });

  @override
  State<ServerConfigScreen> createState() => _ServerConfigScreenState();
}

class _ServerConfigScreenState extends State<ServerConfigScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController();
  bool _isLoading = false;
  String _currentUrl = '';
  String _connectionStatus = '';

  @override
  void initState() {
    super.initState();
    _loadCurrentConfig();
  }

  Future<void> _loadCurrentConfig() async {
    final config = await getServerConfig();
    setState(() {
      _ipController.text = config['ip'] ?? '10.0.2.2';
      _portController.text = config['port'] ?? '3000';
      _currentUrl = widget.apiClient.getCurrentUrl();
    });
    _testConnection();
  }

  Future<void> _testConnection() async {
    setState(() {
      _connectionStatus = 'Проверка соединения...';
    });

    try {
      // Простая проверка доступности сервера
      final testResponse = await widget.apiClient.getUsers();
      
      if (testResponse.success) {
        setState(() {
          _connectionStatus = '✓ Соединение установлено';
        });
      } else {
        setState(() {
          _connectionStatus = '✗ Ошибка: ${testResponse.error}';
        });
      }
    } catch (e) {
      setState(() {
        _connectionStatus = '✗ Ошибка соединения: $e';
      });
    }
  }

  Future<void> _saveConfig() async {
    if (_ipController.text.isEmpty || _portController.text.isEmpty) {
      _showError('Заполните IP и порт');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await widget.apiClient.setServerConfig(
        _ipController.text.trim(),
        _portController.text.trim(),
      );

      await _testConnection();

      _showSuccess('Настройки сохранены!');
      widget.onConfigSaved();
    } catch (e) {
      _showError('Ошибка: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

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

  void _useLocalhost() {
    setState(() {
      _ipController.text = '10.0.2.2';
      _portController.text = '3000';
    });
  }

  void _useLocalNetwork() {
    setState(() {
      _ipController.text = '192.168.1.1';
      _portController.text = '3000';
    });
  }

  void _useLocalhostIPv4() {
    setState(() {
      _ipController.text = '127.0.0.1';
      _portController.text = '3000';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки сервера'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            widget.onConfigSaved();
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Текущие настройки:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text('URL: $_currentUrl'),
                    const SizedBox(height: 8),
                    Text(
                      _connectionStatus,
                      style: TextStyle(
                        color: _connectionStatus.contains('✓') 
                            ? Colors.green 
                            : Colors.red,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'IP адрес сервера',
                border: OutlineInputBorder(),
                hintText: '192.168.1.100 или 10.0.2.2',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              decoration: const InputDecoration(
                labelText: 'Порт сервера',
                border: OutlineInputBorder(),
                hintText: '3000',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 20),
            const Text(
              'Быстрые настройки:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton(
                  onPressed: _useLocalhost,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade100,
                    foregroundColor: Colors.blue.shade800,
                  ),
                  child: const Text('Android эмулятор'),
                ),
                ElevatedButton(
                  onPressed: _useLocalhostIPv4,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade100,
                    foregroundColor: Colors.green.shade800,
                  ),
                  child: const Text('Локальный хост'),
                ),
                ElevatedButton(
                  onPressed: _useLocalNetwork,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade100,
                    foregroundColor: Colors.orange.shade800,
                  ),
                  child: const Text('Локальная сеть'),
                ),
                ElevatedButton(
                  onPressed: _testConnection,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade100,
                    foregroundColor: Colors.purple.shade800,
                  ),
                  child: const Text('Проверить связь'),
                ),
              ],
            ),
            const SizedBox(height: 20),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _saveConfig,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: const Text('Сохранить настройки'),
                  ),
            const SizedBox(height: 20),
            const Text(
              'Подсказки:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text('• Для Android эмулятора: 10.0.2.2:3000'),
            const Text('• Для локального хоста: 127.0.0.1:3000'),
            const Text('• Для телефона в WiFi: IP компьютера:3000'),
            const Text('• Убедитесь, что сервер запущен и доступен'),
          ],
        ),
      ),
    );
  }
}
