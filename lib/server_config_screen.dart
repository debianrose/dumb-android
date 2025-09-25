import 'package:flutter/material.dart';
import 'api_client.dart';
import 'utils.dart';
import 'l10n/app_localizations.dart';

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
      _connectionStatus = AppLocalizations.of(context).loading;
    });

    try {
      final testResponse = await widget.apiClient.getUsers();
      
      if (testResponse.success) {
        setState(() {
          _connectionStatus = '✓ ${AppLocalizations.of(context).success}';
        });
      } else {
        setState(() {
          _connectionStatus = '✗ ${AppLocalizations.of(context).error}: ${testResponse.error}';
        });
      }
    } catch (e) {
      setState(() {
        _connectionStatus = '✗ ${AppLocalizations.of(context).error}: $e';
      });
    }
  }

  Future<void> _saveConfig() async {
    if (_ipController.text.isEmpty || _portController.text.isEmpty) {
      _showError('${AppLocalizations.of(context).error}');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await widget.apiClient.setServerConfig(
        _ipController.text.trim(),
        _portController.text.trim(),
      );

      await _testConnection();
      _showSuccess(AppLocalizations.of(context).success);
      widget.onConfigSaved();
    } catch (e) {
      _showError('${AppLocalizations.of(context).error}: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

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
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(loc.serverSettings),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onConfigSaved,
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
                    Text(
                      loc.currentSettings,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.link, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _currentUrl,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 12,
                          color: _connectionStatus.contains('✓') 
                              ? Colors.green 
                              : colorScheme.error,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _connectionStatus,
                            style: TextStyle(
                              color: _connectionStatus.contains('✓') 
                                  ? Colors.green 
                                  : colorScheme.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _ipController,
              decoration: InputDecoration(
                labelText: loc.serverIp,
                prefixIcon: const Icon(Icons.computer),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _portController,
              decoration: InputDecoration(
                labelText: loc.serverPort,
                prefixIcon: const Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 24),
            Text(
              loc.quickSettings,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilterChip(
                  label: Text(loc.androidEmulator),
                  onSelected: (_) => _useLocalhost(),
                ),
                FilterChip(
                  label: Text(loc.localhost),
                  onSelected: (_) => _useLocalhostIPv4(),
                ),
                FilterChip(
                  label: Text(loc.localNetwork),
                  onSelected: (_) => _useLocalNetwork(),
                ),
                FilterChip(
                  label: Text(loc.testConnection),
                  onSelected: (_) => _testConnection(),
                ),
              ],
            ),
            const SizedBox(height: 24),
            _isLoading
                ? const Center(child: CircularProgressIndicator())
                : FilledButton(
                    onPressed: _saveConfig,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                    child: Text(loc.saveSettings),
                  ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loc.hints,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    _buildHintItem('Android:', '10.0.2.2:3000'),
                    _buildHintItem('Localhost:', '127.0.0.1:3000'),
                    _buildHintItem('WiFi:', 'IP:3000'),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHintItem(String title, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• '),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: Theme.of(context).textTheme.bodyMedium,
                children: [
                  TextSpan(text: '$title ', style: const TextStyle(fontWeight: FontWeight.bold)),
                  TextSpan(text: description),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
