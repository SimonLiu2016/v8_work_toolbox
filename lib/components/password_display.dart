import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_theme.dart';

class PasswordDisplay extends StatefulWidget {
  final String encryptionPassword;

  const PasswordDisplay({super.key, required this.encryptionPassword});

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
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.space12,
                      vertical: AppTheme.space8,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.bgInput,
                      border: Border.all(color: AppTheme.borderSubtle),
                      borderRadius: AppTheme.borderRadiusSmall,
                    ),
                    child: Text(
                      widget.encryptionPassword,
                      style: AppTheme.fontMono.copyWith(color: AppTheme.accentLight),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _copyPasswordToClipboard,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('复制'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '注意：密码已固定为 "!QAZ2wsx#EDC\$#@!"，解密此工具生成的包需使用相同密码。',
              style: AppTheme.fontCaption.copyWith(color: AppTheme.warning),
            ),
          ],
        ),
      ),
    );
  }
}
