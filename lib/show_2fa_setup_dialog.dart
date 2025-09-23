import 'package:flutter/material.dart';

class Show2FASetupDialog extends StatelessWidget {
  final String secret;
  final String qrCodeUrl;
  final Function(String) onTokenEntered;

  Show2FASetupDialog({
    required this.secret,
    required this.qrCodeUrl,
    required this.onTokenEntered,
  });

  final TextEditingController _tokenController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Setup 2FA'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Scan the QR code with your authenticator app:'),
            SizedBox(height: 16),
            Container(
              padding: EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey),
              ),
              child: Text('QR Code would be displayed here'),
              // В реальном приложении здесь будет отображаться QR-код
              // Image.network(qrCodeUrl)
            ),
            SizedBox(height: 16),
            Text('Or enter this secret manually:'),
            SizedBox(height: 8),
            SelectableText(
              secret,
              style: TextStyle(fontFamily: 'monospace', fontSize: 16),
            ),
            SizedBox(height: 16),
            Text('Enter the 6-digit code from your app:'),
            SizedBox(height: 8),
            TextField(
              controller: _tokenController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              decoration: InputDecoration(
                labelText: '6-digit code',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final token = _tokenController.text.trim();
            if (token.length == 6) {
              onTokenEntered(token);
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Please enter a valid 6-digit code'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: Text('Verify'),
        ),
      ],
    );
  }
}
