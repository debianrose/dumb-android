import 'package:flutter/material.dart';

class Disable2FADialog extends StatelessWidget {
  final Function(String) onPasswordEntered;

  Disable2FADialog({required this.onPasswordEntered});

  final TextEditingController _passwordController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Disable 2FA'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Please enter your password to disable Two-Factor Authentication'),
          SizedBox(height: 16),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: InputDecoration(
              labelText: 'Password',
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
            final password = _passwordController.text.trim();
            if (password.length >= 4) {
              onPasswordEntered(password);
              Navigator.pop(context);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Please enter your password'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          },
          child: Text('Confirm'),
        ),
      ],
    );
  }
}
