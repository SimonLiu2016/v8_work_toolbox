import 'package:flutter/material.dart';
import '../../../theme/app_theme.dart';
import '../database/ops_database.dart';
import '../models/ops_models.dart';
import '../services/email_service.dart';

class OpsEmailView extends StatefulWidget {
  final String? initialHtml;
  final String? initialSubject;

  const OpsEmailView({super.key, this.initialHtml, this.initialSubject});

  @override
  State<OpsEmailView> createState() => _OpsEmailViewState();
}

class _OpsEmailViewState extends State<OpsEmailView> {
  List<EmailAccount> _accounts = [];
  EmailAccount? _selectedAccount;
  List<EmailRecipient> _recipients = [];
  final Set<String> _selectedRecipientIds = {};

  final _subjectCtrl = TextEditingController();
  final _htmlCtrl = TextEditingController();

  bool _loading = true;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _subjectCtrl.text = widget.initialSubject ?? '运维运营报告';
    _htmlCtrl.text = widget.initialHtml ?? '<p>你好，这是一封自动投递的运维报告邮件。</p>';
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    final accs = await OpsDatabase.instance.loadEmailAccounts();
    if (mounted) {
      setState(() {
        _accounts = accs;
        if (accs.isNotEmpty && _selectedAccount == null) {
          _selectedAccount = accs.first;
        }
        _loading = false;
      });
      if (_selectedAccount != null) {
        _loadRecipients(_selectedAccount!.id);
      }
    }
  }

  Future<void> _loadRecipients(String accountId) async {
    final list = await OpsDatabase.instance.loadEmailRecipients(accountId);
    if (mounted) {
      setState(() {
        _recipients = list;
        _selectedRecipientIds.addAll(list.map((r) => r.id));
      });
    }
  }

  void _showAddAccountDialog([EmailAccount? existing]) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final hostCtrl = TextEditingController(
      text: existing?.smtpHost ?? 'smtp.example.com',
    );
    final portCtrl = TextEditingController(
      text: existing?.smtpPort.toString() ?? '465',
    );
    final userCtrl = TextEditingController(text: existing?.username ?? '');
    // 编辑态不回填已存授权码：留空即保存时保持原值（见 change spec「编辑既有凭据时留空表示保持原值」）。
    final passCtrl = TextEditingController();
    bool useTls = existing?.useTls ?? true;
    bool passVisible = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: context.bgCard,
          title: Text(
            existing == null ? '添加 SMTP 邮箱账户' : '编辑邮箱账户',
            style: AppTheme.fontTitle,
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '账户标识 (如 工作邮箱)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: hostCtrl,
                          decoration: const InputDecoration(
                            labelText: 'SMTP 服务器',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 1,
                        child: TextField(
                          controller: portCtrl,
                          decoration: const InputDecoration(labelText: '端口'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: userCtrl,
                    decoration: InputDecoration(labelText: '发件人邮箱 / 用户名'),
                  ),
                  SizedBox(height: 10),
                  TextField(
                    controller: passCtrl,
                    obscureText: !passVisible,
                    decoration: InputDecoration(
                      labelText: '邮箱授权码 / 密码',
                      helperText: existing == null ? null : '留空则保持原有授权码不变',
                      suffixIcon: IconButton(
                        icon: Icon(
                          passVisible ? Icons.visibility : Icons.visibility_off,
                          size: 16,
                          color: context.textSecondary,
                        ),
                        tooltip: passVisible ? '隐藏授权码' : '显示授权码',
                        onPressed: () =>
                            setDialogState(() => passVisible = !passVisible),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    title: const Text('启用 SSL/TLS 加密'),
                    value: useTls,
                    activeColor: context.accentSolid,
                    onChanged: (v) => setDialogState(() => useTls = v),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: context.accentSolid),
              onPressed: () async {
                final item = EmailAccount(
                  id: existing?.id,
                  name: nameCtrl.text.trim(),
                  smtpHost: hostCtrl.text.trim(),
                  smtpPort: int.tryParse(portCtrl.text.trim()) ?? 465,
                  username: userCtrl.text.trim(),
                  password: passCtrl.text.trim().isEmpty
                      ? (existing?.password ?? '')
                      : passCtrl.text.trim(),
                  useTls: useTls,
                );
                await OpsDatabase.instance.saveEmailAccount(item);
                if (ctx.mounted) Navigator.pop(ctx);
                _loadAll();
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddRecipientDialog() {
    if (_selectedAccount == null) return;
    final nameCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    final groupCtrl = TextEditingController(text: '运维组');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: context.bgCard,
        title: const Text('添加收件人', style: AppTheme.fontTitle),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: '姓名'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: emailCtrl,
                decoration: const InputDecoration(labelText: '电子邮箱地址'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: groupCtrl,
                decoration: const InputDecoration(labelText: '分组名称'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: context.accentSolid),
            onPressed: () async {
              final r = EmailRecipient(
                accountId: _selectedAccount!.id,
                name: nameCtrl.text.trim(),
                email: emailCtrl.text.trim(),
                groupName: groupCtrl.text.trim(),
              );
              await OpsDatabase.instance.saveEmailRecipient(r);
              if (ctx.mounted) Navigator.pop(ctx);
              _loadRecipients(_selectedAccount!.id);
            },
            child: const Text('添加'),
          ),
        ],
      ),
    );
  }

  Future<void> _sendEmail() async {
    if (_selectedAccount == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择发件账户')));
      return;
    }

    final targetRecipients = _recipients
        .where((r) => _selectedRecipientIds.contains(r.id))
        .toList();
    if (targetRecipients.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请至少勾选一个收件人')));
      return;
    }

    setState(() => _sending = true);
    try {
      await EmailService.instance.sendReportEmail(
        account: _selectedAccount!,
        recipients: targetRecipients,
        subject: _subjectCtrl.text.trim(),
        htmlContent: _htmlCtrl.text,
      );

      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('邮件成功投递给 ${targetRecipients.length} 位收件人！'),
            backgroundColor: context.successSolid,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('发信失败: $e'), backgroundColor: context.errorSolid),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(
      padding: const EdgeInsets.all(AppTheme.space24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 左侧：账户与通讯录
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('SMTP 邮箱账户', style: AppTheme.fontTitle),
                    IconButton(
                      icon: Icon(Icons.add, size: 20),
                      onPressed: () => _showAddAccountDialog(),
                      tooltip: '添加账户',
                    ),
                  ],
                ),
                SizedBox(height: 8),
                DropdownButtonFormField<EmailAccount>(
                  value: _selectedAccount,
                  dropdownColor: context.bgCard,
                  decoration: const InputDecoration(labelText: '当前发信账户'),
                  items: _accounts
                      .map(
                        (a) => DropdownMenuItem(value: a, child: Text(a.name)),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedAccount = v);
                    if (v != null) _loadRecipients(v.id);
                  },
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('收件人通讯录', style: AppTheme.fontTitle),
                    IconButton(
                      icon: Icon(
                        Icons.person_add_alt_1_rounded,
                        size: 20,
                      ),
                      onPressed: _showAddRecipientDialog,
                      tooltip: '添加收件人',
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: context.bgCard,
                      borderRadius: AppTheme.borderRadiusMedium,
                      border: Border.all(color: context.borderSubtle),
                    ),
                    child: _recipients.isEmpty
                        ? Center(
                            child: Text(
                              '当前账户下暂无收件人',
                              style: AppTheme.fontBodySecondary,
                            ),
                          )
                        : ListView.separated(
                            itemCount: _recipients.length,
                            separatorBuilder: (_, __) => Divider(
                              height: 1,
                              color: context.borderSubtle,
                            ),
                            itemBuilder: (context, idx) {
                              final r = _recipients[idx];
                              final isChecked = _selectedRecipientIds.contains(
                                r.id,
                              );
                              return CheckboxListTile(
                                value: isChecked,
                                activeColor: context.accentSolid,
                                title: Text(r.name, style: AppTheme.fontBody),
                                subtitle: Text(
                                  '${r.email} (${r.groupName})',
                                  style: AppTheme.fontCaption,
                                ),
                                onChanged: (val) {
                                  setState(() {
                                    if (val == true) {
                                      _selectedRecipientIds.add(r.id);
                                    } else {
                                      _selectedRecipientIds.remove(r.id);
                                    }
                                  });
                                },
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.space24),

          // 右侧：邮件发送编辑工作台
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('邮件发送工作台', style: AppTheme.fontTitle),
                const SizedBox(height: 12),
                TextField(
                  controller: _subjectCtrl,
                  decoration: const InputDecoration(labelText: '邮件主题'),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TextField(
                    controller: _htmlCtrl,
                    maxLines: null,
                    expands: true,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      labelText: '邮件正文 (HTML / Text)',
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded, size: 20),
                    label: Text(
                      _sending
                          ? '正在投递邮件...'
                          : '立即发送报告邮件 (${_selectedRecipientIds.length} 位收件人)',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: context.accentSolid,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _sending ? null : _sendEmail,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
