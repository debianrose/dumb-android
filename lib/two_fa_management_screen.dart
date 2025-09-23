import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'disable_2fa_dialog.dart';
import 'show_2fa_setup_dialog.dart';

class TwoFAManagementScreen extends StatefulWidget {
  final String token;
  final String username;

  TwoFAManagementScreen({required this.token, required this.username});

  @override
  _TwoFAManagementScreenState createState() => _TwoFAManagementScreenState();
}

class _TwoFAManagementScreenState extends State<TwoFAManagementScreen> {
  bool _is2FAEnabled = false;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _load2FAStatus();
  }

  Future<void> _load2FAStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.get(
        Uri.parse('http://95.81.122.186:3000/api/2fa/status'),
        headers: {
          'Authorization': 'Bearer ${widget.token}',
        },
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        setState(() {
          _is2FAEnabled = result['enabled'] ?? false;
        });
      } else {
        _showError('Failed to load 2FA status');
      }
    } catch (e) {
      _showError('Failed to load 2FA status');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _setup2FA() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/2fa/setup'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({}),
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        final secret = result['secret'];
        final qrCodeUrl = result['qrCodeUrl'];
        
        _show2FASetupDialog(secret, qrCodeUrl);
      } else {
        _showError('Failed to setup 2FA');
      }
    } catch (e) {
      _showError('Failed to setup 2FA');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _show2FASetupDialog(String secret, String qrCodeUrl) {
    showDialog(
      context: context,
      builder: (context) => Show2FASetupDialog(
        secret: secret,
        qrCodeUrl: qrCodeUrl,
        onTokenEntered: _verify2FASetup,
      ),
    );
  }

  Future<void> _verify2FASetup(String token) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/2fa/enable'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({'token': token}),
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        _showSuccess('2FA enabled successfully');
        await _load2FAStatus();
      } else {
        _showError('Failed to enable 2FA');
      }
    } catch (e) {
      _showError('Failed to enable 2FA');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _disable2FA() {
    showDialog(
      context: context,
      builder: (context) => Disable2FADialog(
        onPasswordEntered: _confirmDisable2FA,
      ),
    );
  }

  Future<void> _confirmDisable2FA(String password) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('http://95.81.122.186:3000/api/2fa/disable'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${widget.token}',
        },
        body: json.encode({'password': password}),
      );

      final result = json.decode(response.body);
      
      if (result['success'] == true) {
        _showSuccess('2FA disabled successfully');
        await _load2FAStatus();
      } else {
        _showError(result['error'] ?? 'Failed to disable 2FA');
      }
    } catch (e) {
      _showError('Failed to disable 2FA');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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
      appBar: AppBar(title: Text('2FA Management')),
      body: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Two-Factor Authentication',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),
                    Row(
                      children: [
                        Text('Status:'),
                        SizedBox(width: 8),
                        Chip(
                          label: Text(
                            _is2FAEnabled ? 'Enabled' : 'Disabled',
                            style: TextStyle(color: Colors.white),
                          ),
                          backgroundColor: _is2FAEnabled ? Colors.green : Colors.grey,
                        ),
                      ],
                    ),
                    SizedBox(height: 16),
                    if (_isLoading)
                      Center(child: CircularProgressIndicator())
                    else
                      Column(
                        children: [
                          if (!_is2FAEnabled)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _setup2FA,
                                child: Text('Enable 2FA'),
                              ),
                            )
                          else
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: _disable2FA,
                                child: Text('Disable 2FA'),
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
