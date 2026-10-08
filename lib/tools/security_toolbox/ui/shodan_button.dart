/// 「外部情报查询」按钮：对单个资产触发 Shodan 查询并合并结果。
///
/// 抽成独立控件而不是内联在列表行里：LAN 与 Web 两个面板都要用，
/// 且各自的导航/提示逻辑完全相同（未配 Key 引导配置、未装 CLI 引导安装）。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/security_enums.dart';
import '../models/security_models.dart';
import '../services/security_process_runner.dart';
import '../services/security_session_controller.dart';
import '../services/security_settings_store.dart';
import '../services/web_recon_services.dart';

class ShodanButton extends StatefulWidget {
  final PentestAsset asset;
  final SecuritySessionController controller;

  const ShodanButton({
    super.key,
    required this.asset,
    required this.controller,
  });

  @override
  State<ShodanButton> createState() => _ShodanButtonState();
}

class _ShodanButtonState extends State<ShodanButton> {
  bool _busy = false;

  Future<void> _query() async {
    final controller = widget.controller;
    final store = SecuritySettingsStore.instance;

    final key = await store.shodanKey();
    if (key.isEmpty) {
      await _promptForKey(store);
      return;
    }
    if (resolveExecutable(ShodanService.cli) == null) {
      _toast('未安装 shodan CLI，请到「工具依赖」安装（brew install shodan）');
      return;
    }

    setState(() => _busy = true);
    controller.log('Shodan 查询 ${widget.asset.address} …');
    try {
      final result = await ShodanService.queryIp(
        widget.asset.address,
        key,
      );
      if (result == null) {
        controller.log('Shodan 查询失败或无结果');
        _toast('Shodan 查询失败或无结果');
        return;
      }
      final merged = ShodanService.mergeShodan(
        widget.asset.metadata,
        result,
      );
      await controller.assets.upsert(
        sessionId: widget.asset.sessionId,
        type: widget.asset.type,
        address: widget.asset.address,
        metadata: merged,
      );
      await controller.reloadSessionData();
      await controller.recordEvent(
        eventType: TimelineEventType.statusChange,
        title: 'Shodan 情报合并: ${widget.asset.address}',
        detail: {'cves': merged['shodan']?['vulns'] ?? const []},
      );
      final vulns = (merged['shodan']?['vulns'] as List?) ?? const [];
      _toast(
        vulns.isEmpty ? '已合并 Shodan 情报' : '已合并，命中 ${vulns.length} 个 CVE',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Key 输入对话框。保存成功后立刻重试查询——用户不会想再点一次。
  Future<void> _promptForKey(SecuritySettingsStore store) async {
    final keyController = TextEditingController();
    final key = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: context.bgCard,
        title: Text('配置 Shodan API Key', style: context.fontTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Key 保存在本地配置中，可从 account.shodan.io 随时轮换。',
              style: context.fontCaption,
            ),
            const SizedBox(height: AppTheme.space8),
            TextField(
              controller: keyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                isDense: true,
              ),
              style: context.fontBody,
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, keyController.text.trim()),
            child: const Text('保存并查询'),
          ),
        ],
      ),
    );
    keyController.dispose();
    if (key == null || key.isEmpty) return;
    await store.saveShodanKey(key);
    // 递归一次即可：保存后 key 已就位，不会再次进入引导分支。
    await _query();
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: _busy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.travel_explore, size: 16, color: context.textSecondary),
      tooltip: '外部情报查询（Shodan）',
      visualDensity: VisualDensity.compact,
      onPressed: _busy ? null : _query,
    );
  }
}
