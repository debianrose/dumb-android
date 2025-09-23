import 'package:flutter/material.dart';

class TwoFADialog extends StatelessWidget {
  final String sessionId;
  final String username;
  final Function(String) onTokenEntered;

  TwoFADialog({
    required this.sessionId,
    required this.username,
    required this.onTokenEntered,
  });

  final TextEditingController _tokenController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Two-Factor Authentication'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Please enter the 6-digit code from your authenticator app'),
          SizedBox(height: 16),
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
