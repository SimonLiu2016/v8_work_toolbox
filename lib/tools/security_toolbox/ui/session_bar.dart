/// 会话选择 UI：新建 LAN/Web 会话、历史会话列表、当前会话切换。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/security_enums.dart';
import '../models/security_models.dart';
import '../services/lan_recon_services.dart';
import '../services/security_session_controller.dart';
import 'widgets.dart';

/// 顶部的会话工具条。
///
/// 「当前没有会话」和「有会话但没选」是两种状态，报错必须分开——前者要引导新建，
/// 后者只是要用户点一下。合成一个"请选择会话"会让用户以为数据丢了。
class SessionBar extends StatelessWidget {
  final SecuritySessionController controller;
  final VoidCallback onCreateLan;
  final VoidCallback onCreateWeb;

  const SessionBar({
    super.key,
    required this.controller,
    required this.onCreateLan,
    required this.onCreateWeb,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final current = controller.current;
        return Container(
          padding: const EdgeInsets.all(AppTheme.space12),
          decoration: BoxDecoration(
            color: context.bgCard,
            border: Border(bottom: BorderSide(color: context.borderSubtle)),
          ),
          child: Row(
            children: [
              Icon(Icons.shield_outlined, size: 18, color: context.accentText),
              const SizedBox(width: AppTheme.space8),
              Expanded(
                child: current == null
                    ? Text(
                        controller.sessionList.isEmpty
                            ? '还没有渗透会话'
                            : '尚未选择会话',
                        style: context.fontBodySecondary,
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Text(current.name, style: context.fontBody),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: context.accentSubtle,
                                  borderRadius: AppTheme.borderRadiusSmall,
                                ),
                                child: Text(
                                  SessionType.labelOf(current.type),
                                  style: AppTheme.fontCaption.copyWith(
                                    color: context.accentText,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: context.bgInput,
                                  borderRadius: AppTheme.borderRadiusSmall,
                                ),
                                child: Text(
                                  SessionStatus.labelOf(current.status),
                                  style: context.fontCaption,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '范围: ${current.scope.isEmpty ? '未设置' : current.scope.join('、')}'
                            ' · 资产 ${controller.assetList.length}'
                            ' · 发现 ${controller.findingList.length}',
                            style: context.fontCaption,
                          ),
                        ],
                      ),
              ),
              if (current != null) ...[
                IconButton(
                  tooltip: '删除当前会话',
                  icon: Icon(Icons.delete_outline, size: 18, color: context.textTertiary),
                  onPressed: () => _confirmDeleteSession(context, controller, current),
                ),
                const SizedBox(width: AppTheme.space4),
              ],
              if (controller.sessionList.isNotEmpty) ...[
                _SessionSwitcher(controller: controller),
                const SizedBox(width: AppTheme.space8),
              ],
              SmallActionButton(
                label: '新建 LAN 会话',
                icon: Icons.router_outlined,
                onPressed: onCreateLan,
              ),
              const SizedBox(width: AppTheme.space8),
              SmallActionButton(
                label: '新建 Web 会话',
                icon: Icons.language_outlined,
                primary: true,
                onPressed: onCreateWeb,
              ),
            ],
          ),
        );
      },
    );
  }
}

Future<void> _confirmDeleteSession(
  BuildContext context,
  SecuritySessionController controller,
  PentestSession s,
) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: context.bgCard,
      title: Text('删除会话', style: context.fontTitle),
      content: Text(
        '将删除「${s.name}」及其全部资产、发现物与时间线，不可恢复。',
        style: context.fontBody,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: context.errorSolid,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除'),
        ),
      ],
    ),
  );
  if (ok == true) {
    await controller.deleteSession(s.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除会话「${s.name}」')),
      );
    }
  }
}

class _SessionSwitcher extends StatelessWidget {
  final SecuritySessionController controller;

  const _SessionSwitcher({required this.controller});

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: '切换会话',
      color: context.bgCard,
      icon: Icon(Icons.swap_horiz, size: 18, color: context.textSecondary),
      onSelected: (id) => controller.selectSession(id),
      itemBuilder: (context) => [
        for (final s in controller.sessionList)
          PopupMenuItem(
            value: s.id,
            child: Row(
              children: [
                Icon(
                  s.id == controller.current?.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 14,
                  color: context.accentText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${s.name}（${SessionType.labelOf(s.type)}）',
                    style: context.fontBody,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16, color: context.errorSolid),
                  tooltip: '删除会话',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  onPressed: () {
                    Navigator.pop(context);
                    _confirmDeleteSession(context, controller, s);
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// 新建 LAN 会话对话框：目标 CIDR 输入 + 自动填充本机网段。
class NewLanSessionDialog extends StatefulWidget {
  const NewLanSessionDialog({super.key});

  @override
  State<NewLanSessionDialog> createState() => _NewLanSessionDialogState();
}

class _NewLanSessionDialogState extends State<NewLanSessionDialog> {
  final _nameController = TextEditingController();
  final _scopeController = TextEditingController();
  List<NetworkInterface> _interfaces = const [];
  bool _loadingInterfaces = true;

  @override
  void initState() {
    super.initState();
    _detectInterfaces();
  }

  Future<void> _detectInterfaces() async {
    final list = await NetworkInterfaceDetector.detect();
    if (!mounted) return;
    setState(() {
      _interfaces = list;
      _loadingInterfaces = false;
      // 自动填充第一个非 loopback 接口的网段（spec「自动填充网段」）。
      if (_scopeController.text.isEmpty && list.isNotEmpty) {
        final first = list.first;
        final prefix = first.cidr.contains('/') ? first.cidr.split('/')[1] : '24';
        final base = first.ipv4.split('.').take(3).join('.');
        _scopeController.text = '$base.0/$prefix';
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _scopeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.bgCard,
      title: Text('新建局域网会话', style: context.fontTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '会话名称'),
              style: context.fontBody,
            ),
            const SizedBox(height: AppTheme.space12),
            TextField(
              controller: _scopeController,
              decoration: const InputDecoration(
                labelText: '目标网段 (CIDR)',
                hintText: '192.168.1.0/24',
              ),
              style: context.fontBody,
            ),
            const SizedBox(height: AppTheme.space12),
            Text('本机网段（点击填入）', style: context.fontCaption),
            const SizedBox(height: AppTheme.space6),
            if (_loadingInterfaces)
              Text('检测中…', style: context.fontCaption)
            else if (_interfaces.isEmpty)
              Text('未检测到活跃接口', style: context.fontCaption)
            else
              Wrap(
                spacing: AppTheme.space8,
                runSpacing: AppTheme.space8,
                children: [
                  for (final iface in _interfaces)
                    InkWell(
                      onTap: () {
                        final prefix = iface.cidr.contains('/')
                            ? iface.cidr.split('/')[1]
                            : '24';
                        final base = iface.ipv4.split('.').take(3).join('.');
                        _scopeController.text = '$base.0/$prefix';
                      },
                      borderRadius: AppTheme.borderRadiusSmall,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: context.bgInput,
                          borderRadius: AppTheme.borderRadiusSmall,
                          border: Border.all(color: context.borderSubtle),
                        ),
                        child: Text(
                          '${iface.name} ${iface.ipv4}',
                          style: context.fontCaption,
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim().isEmpty
                ? 'LAN 会话 ${DateTime.now().millisecondsSinceEpoch % 10000}'
                : _nameController.text.trim();
            final scope = _scopeController.text
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            Navigator.pop(context, {'name': name, 'scope': scope});
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}

/// 新建 Web 会话对话框：多域名输入。
class NewWebSessionDialog extends StatefulWidget {
  const NewWebSessionDialog({super.key});

  @override
  State<NewWebSessionDialog> createState() => _NewWebSessionDialogState();
}

class _NewWebSessionDialogState extends State<NewWebSessionDialog> {
  final _nameController = TextEditingController();
  final _scopeController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _scopeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: context.bgCard,
      title: Text('新建 Web 资产会话', style: context.fontTitle),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: '会话名称'),
              style: context.fontBody,
            ),
            const SizedBox(height: AppTheme.space12),
            TextField(
              controller: _scopeController,
              decoration: const InputDecoration(
                labelText: '根域名（每行一个）',
                hintText: 'example.com',
              ),
              style: context.fontBody,
              maxLines: 4,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameController.text.trim().isEmpty
                ? 'Web 会话 ${DateTime.now().millisecondsSinceEpoch % 10000}'
                : _nameController.text.trim();
            final scope = _scopeController.text
                .split(RegExp(r'[\n,;]'))
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
            Navigator.pop(context, {'name': name, 'scope': scope});
          },
          child: const Text('创建'),
        ),
      ],
    );
  }
}

/// 显示新建会话对话框并执行创建。
Future<void> showNewSessionDialog(
  BuildContext context,
  SecuritySessionController controller,
  String type,
) async {
  final result = await showDialog<Map<String, dynamic>>(
    context: context,
    builder: (context) =>
        type == SessionType.lan
            ? const NewLanSessionDialog()
            : const NewWebSessionDialog(),
  );
  if (result == null) return;
  final session = await controller.createSession(
    name: result['name'] as String,
    type: type,
    scope: (result['scope'] as List).cast<String>(),
  );
  controller.log('已创建会话: ${session.name}');
}
