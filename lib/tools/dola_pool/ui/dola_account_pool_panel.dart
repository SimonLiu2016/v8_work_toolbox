import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/dola_account.dart';
import '../services/dola_account_store.dart';
import '../services/dola_probe_service.dart';

/// Dola 号池账号管理与状态卡片面板。
class DolaAccountPoolPanel extends StatefulWidget {
  const DolaAccountPoolPanel({super.key});

  @override
  State<DolaAccountPoolPanel> createState() => _DolaAccountPoolPanelState();
}

class _DolaAccountPoolPanelState extends State<DolaAccountPoolPanel> {
  final _store = DolaAccountStore.instance;

  @override
  void initState() {
    super.initState();
    _store.init();
    _store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    _store.removeListener(_onStoreChanged);
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    final proxyController = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量导入 Dola 账号 Cookie'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withAlpha(20),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.blue.withAlpha(50)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 16, color: Colors.blueAccent),
                        const SizedBox(width: 6),
                        const Expanded(
                          child: Text(
                            '如何获取 Cookie (sessionid)？',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blueAccent),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () {
                            const script = 'copy(document.cookie.split("; ").find(r=>r.startsWith("sessionid="))||"未找到sessionid");';
                            Clipboard.setData(const ClipboardData(text: script));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('已复制提取脚本！可在 dola.com 控制台粘贴回车，即会自动复制 sessionid 到剪贴板')),
                            );
                          },
                          icon: const Icon(Icons.copy, size: 14),
                          label: const Text('复制提取脚本', style: TextStyle(fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '方式 1：登录 dola.com，按 F12 (或 Cmd+Option+I) 打开控制台 Console，粘贴上面复制的脚本并回车，即可自动将 sessionid 拷入剪贴板。\n'
                      '方式 2：在 Application (应用) -> Cookies -> https://www.dola.com 中找到 sessionid 复制其 Value 粘贴到下方。',
                      style: TextStyle(fontSize: 11, height: 1.4, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                '请粘贴从 dola.com 导出的 Cookie 文本，支持一行一个完整 Cookie 或单独粘贴 sessionid 值：',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 6,
                decoration: const InputDecoration(
                  hintText: 'sessionid=xxx; path=/; domain=.dola.com\n或者直接每行一个 sessionid',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: proxyController,
                decoration: const InputDecoration(
                  labelText: '默认绑定代理 (可选)',
                  hintText: 'http://127.0.0.1:7890',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final text = controller.text.trim();
              if (text.isNotEmpty) {
                final proxy = proxyController.text.trim();
                final messenger = ScaffoldMessenger.of(context);
                final count = await _store.importFromCookieText(
                  text,
                  defaultProxy: proxy.isNotEmpty ? proxy : null,
                );
                if (ctx.mounted) {
                  Navigator.of(ctx).pop();
                  messenger.showSnackBar(
                    SnackBar(content: Text('成功导入 $count 个 Dola 账号')),
                  );
                }
              }
            },
            child: const Text('导入'),
          ),
        ],
      ),
    );
  }

  Future<void> _probeAccount(DolaAccount account) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final res = await DolaProbeService.instance.probeAccount(account);
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text('${account.name}: ${res.message}'),
            backgroundColor: res.isValid ? Colors.green : Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = _store.accounts;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.video_library_outlined, color: Colors.indigo),
                const SizedBox(width: 8),
                const Text(
                  'Dola 视频模型号池 (字节 Seedance 免费池)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重置额度'),
                  onPressed: () async {
                    await _store.resetAllQuotas();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('已重置所有账号今日额度')),
                      );
                    }
                  },
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('导入 Cookie'),
                  onPressed: _showImportDialog,
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (accounts.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24),
                alignment: Alignment.center,
                child: const Text(
                  '当前号池中没有可用账号，请点击右上角「导入 Cookie」添加。',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: accounts.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, index) {
                  final acc = accounts[index];
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(
                      backgroundColor: _statusColor(acc.status).withValues(alpha: 0.15),
                      child: Icon(
                        _statusIcon(acc.status),
                        color: _statusColor(acc.status),
                        size: 20,
                      ),
                    ),
                    title: Row(
                      children: [
                        Text(acc.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        const SizedBox(width: 8),
                        _buildStatusBadge(acc.status),
                      ],
                    ),
                    subtitle: Text(
                      '今日剩余点数: ${acc.points}/${acc.dailyLimit} 点'
                      '${acc.proxyUrl != null ? " · 代理: ${acc.proxyUrl}" : ""}'
                      '${acc.lastError != null ? " · 备注: ${acc.lastError}" : ""}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '探活与余额校正',
                          icon: const Icon(Icons.network_ping, size: 18),
                          onPressed: () => _probeAccount(acc),
                        ),
                        IconButton(
                          tooltip: '删除账号',
                          icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                          onPressed: () => _store.deleteAccount(acc.id),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(DolaAccountStatus status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: _statusColor(status).withValues(alpha: 0.3)),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(fontSize: 11, color: _statusColor(status), fontWeight: FontWeight.bold),
      ),
    );
  }

  Color _statusColor(DolaAccountStatus status) {
    switch (status) {
      case DolaAccountStatus.full:
        return Colors.green;
      case DolaAccountStatus.half:
        return Colors.teal;
      case DolaAccountStatus.cooling:
        return Colors.blueGrey;
      case DolaAccountStatus.busy:
        return Colors.orange;
      case DolaAccountStatus.risk:
        return Colors.red;
      case DolaAccountStatus.abnormal:
        return Colors.purple;
    }
  }

  IconData _statusIcon(DolaAccountStatus status) {
    switch (status) {
      case DolaAccountStatus.full:
        return Icons.check_circle_outline;
      case DolaAccountStatus.half:
        return Icons.pie_chart_outline;
      case DolaAccountStatus.cooling:
        return Icons.nightlight_round;
      case DolaAccountStatus.busy:
        return Icons.hourglass_top;
      case DolaAccountStatus.risk:
        return Icons.warning_amber_rounded;
      case DolaAccountStatus.abnormal:
        return Icons.error_outline;
    }
  }

  String _statusLabel(DolaAccountStatus status) {
    switch (status) {
      case DolaAccountStatus.full:
        return '满额 (4点)';
      case DolaAccountStatus.half:
        return '半额 (2点)';
      case DolaAccountStatus.cooling:
        return '已耗尽冷却';
      case DolaAccountStatus.busy:
        return '生成中';
      case DolaAccountStatus.risk:
        return '风控冷却';
      case DolaAccountStatus.abnormal:
        return '异常';
    }
  }
}
