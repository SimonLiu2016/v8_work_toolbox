import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PasswordDisplay extends StatefulWidget {
  final String encryptionPassword;

  const PasswordDisplay({Key? key, required this.encryptionPassword})
    : super(key: key);

  @override
  State<PasswordDisplay> createState() => _PasswordDisplayState();
}

class _PasswordDisplayState extends State<PasswordDisplay> {
  void _copyPasswordToClipboard() {
    Clipboard.setData(ClipboardData(text: widget.encryptionPassword));
    _showSuccessDialog('密码已复制到剪贴板');
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('成功'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '加密密码',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(widget.encryptionPassword),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _copyPasswordToClipboard,
                  child: const Text('复制'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              '注意：密码已固定为 "!QAZ2wsx#EDC\$#@!"，请妥善保管。',
              style: TextStyle(color: Colors.red),
            ),
          ],
        ),
      ),
    );
  }
}
