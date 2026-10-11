import 'package:flutter/material.dart';

import '../services/registrar_config_store.dart';

class RegistrarCredentialsDialog extends StatefulWidget {
  const RegistrarCredentialsDialog({super.key});

  @override
  State<RegistrarCredentialsDialog> createState() => _RegistrarCredentialsDialogState();
}

class _RegistrarCredentialsDialogState extends State<RegistrarCredentialsDialog> {
  final _store = RegistrarConfigStore.instance;

  late final TextEditingController _smsKeyController;
  late final TextEditingController _smsCountryController;
  late final TextEditingController _recoveryEmailController;
  late final TextEditingController _imapAuthController;
  late final TextEditingController _imapServerController;
  late final TextEditingController _imapPortController;
  late final TextEditingController _capSolverKeyController;

  bool _obscureSmsKey = true;
  bool _obscureImapAuth = true;
  bool _obscureCapSolverKey = true;

  @override
  void initState() {
    super.initState();
    final cfg = _store.config;
    _smsKeyController = TextEditingController(text: cfg.smsApiKey);
    _smsCountryController = TextEditingController(text: cfg.smsCountry);
    _recoveryEmailController = TextEditingController(text: cfg.recoveryEmail);
    _imapAuthController = TextEditingController(text: cfg.imapAuth);
    _imapServerController = TextEditingController(text: cfg.imapServer);
    _imapPortController = TextEditingController(text: cfg.imapPort.toString());
    _capSolverKeyController = TextEditingController(text: cfg.capSolverApiKey);
  }

  @override
  void dispose() {
    _smsKeyController.dispose();
    _smsCountryController.dispose();
    _recoveryEmailController.dispose();
    _imapAuthController.dispose();
    _imapServerController.dispose();
    _imapPortController.dispose();
    _capSolverKeyController.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    final port = int.tryParse(_imapPortController.text.trim()) ?? 993;
    final updated = _store.config.copyWith(
      smsApiKey: _smsKeyController.text.trim(),
      smsCountry: _smsCountryController.text.trim(),
      recoveryEmail: _recoveryEmailController.text.trim(),
      imapAuth: _imapAuthController.text.trim(),
      imapServer: _imapServerController.text.trim(),
      imapPort: port,
      capSolverApiKey: _capSolverKeyController.text.trim(),
    );

    await _store.save(updated);
    if (mounted) {
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已成功保存接码与邮箱凭据配置！')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.shield_outlined, size: 24),
                  const SizedBox(width: 8),
                  Text('固定凭证与服务配置', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              Text(
                '配置一次即永久自动落盘，后续启动注册无需再次输入。',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
              const SizedBox(height: 20),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    // 安全恢复邮箱与 IMAP
                    Text('1. 安全恢复邮箱绑定 (QQ 邮箱)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _recoveryEmailController,
                      decoration: const InputDecoration(
                        labelText: '安全恢复邮箱地址',
                        hintText: '如: your_qq@qq.com',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _imapAuthController,
                      obscureText: _obscureImapAuth,
                      decoration: InputDecoration(
                        labelText: 'QQ 邮箱 IMAP 授权码',
                        hintText: '16位授权码 (非QQ登录密码)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(_obscureImapAuth ? Icons.visibility : Icons.visibility_off, size: 18),
                          onPressed: () => setState(() => _obscureImapAuth = !_obscureImapAuth),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _imapServerController,
                            decoration: const InputDecoration(
                              labelText: 'IMAP 服务器',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 1,
                          child: TextField(
                            controller: _imapPortController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: '端口',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    // SMS 接码配置
                    Text('2. SMS-Activate 平台接码 (可选)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _smsKeyController,
                      obscureText: _obscureSmsKey,
                      decoration: InputDecoration(
                        labelText: 'SMS-Activate API Key',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(_obscureSmsKey ? Icons.visibility : Icons.visibility_off, size: 18),
                          onPressed: () => setState(() => _obscureSmsKey = !_obscureSmsKey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _smsCountryController,
                      decoration: const InputDecoration(
                        labelText: '接码国家代码 (0 代表俄罗斯/任意便宜国家)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const Divider(height: 32),
                    // CapSolver 备用
                    Text('3. CapSolver 打码平台 (可选)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _capSolverKeyController,
                      obscureText: _obscureCapSolverKey,
                      decoration: InputDecoration(
                        labelText: 'CapSolver API Key',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: Icon(_obscureCapSolverKey ? Icons.visibility : Icons.visibility_off, size: 18),
                          onPressed: () => setState(() => _obscureCapSolverKey = !_obscureCapSolverKey),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('保存凭据配置'),
                    onPressed: _handleSave,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
