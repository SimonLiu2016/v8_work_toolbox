import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../theme/app_theme.dart';
import '../services/password_health.dart';
import '../vault_models.dart';
import '../vault_store.dart';

/// 体检报告面板（spec：Password health report + Opt-in breach checking）
///
/// 纯本地计算（强度/重复/年龄）；泄露检测仅按条目手动触发，
/// 发送 SHA-1 前缀（k-匿名）到 HIBP 兼容 API。
class HealthReportPanel extends StatefulWidget {
  const HealthReportPanel({
    super.key,
    required this.store,
    required this.onNavigateToItem,
  });

  final VaultStore store;
  final ValueChanged<VaultItem> onNavigateToItem;

  @override
  State<HealthReportPanel> createState() => _HealthReportPanelState();
}

class _HealthReportPanelState extends State<HealthReportPanel> {
  final PasswordHealth _health = PasswordHealth();
  bool _loading = true;
  String? _error;

  List<WeakPasswordEntry> _weak = [];
  List<DuplicateGroup> _duplicates = [];
  List<VaultItem> _aged = [];
  final Map<String, int?> _breachResults = {};

  @override
  void initState() {
    super.initState();
    _runAudit();
  }

  Future<void> _runAudit() async {
    try {
      final items = widget.store.items
          .where((e) => e.type == VaultEntryType.login)
          .toList();
      final passwords = <String, String>{};
      for (final item in items) {
        try {
          final secret = await widget.store.readSecret(item.id);
          passwords[item.id] = secret.secret;
        } catch (_) {
          // 单条解密失败跳过
        }
      }

      final weak = <WeakPasswordEntry>[];
      final titleById = {for (final i in items) i.id: i.title};
      passwords.forEach((id, pwd) {
        if (pwd.isEmpty) return;
        final score = _health.score(pwd);
        if (score < PasswordHealth.weakThreshold) {
          weak.add(WeakPasswordEntry(
            itemId: id,
            title: titleById[id] ?? '',
            score: score,
          ));
        }
      });
      weak.sort((a, b) => a.score.compareTo(b.score));

      final dupMap = _health.findDuplicates(passwords);
      final duplicates = dupMap.entries
          .map((e) => DuplicateGroup(
                itemIds: e.value,
                titles:
                    e.value.map((id) => titleById[id] ?? '').toList(),
              ))
          .toList();

      final aged = _health.findAged(items);

      if (mounted) {
        setState(() {
          _weak = weak;
          _duplicates = duplicates;
          _aged = aged;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// k-匿名泄露检测：只发送 SHA-1 前 8 hex
  Future<void> _checkBreach(WeakPasswordEntry entry) async {
    setState(() => _breachResults[entry.itemId] = -1); // loading
    try {
      final secret = await widget.store.readSecret(entry.itemId);
      final sha1Hex = sha1.convert(utf8.encode(secret.secret)).toString().toUpperCase();
      final prefix = sha1Hex.substring(0, 8);
      final suffix = sha1Hex.substring(8).toUpperCase();

      final uri = Uri.parse(
          'https://api.pwnedpasswords.com/range/$prefix');
      final resp = await http.get(uri).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200) {
        final hit = resp.body
            .split('\n')
            .any((line) => line.startsWith(suffix));
        if (mounted) {
          setState(() => _breachResults[entry.itemId] = hit ? 1 : 0);
        }
      } else {
        if (mounted) {
          setState(() => _breachResults[entry.itemId] = null);
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _breachResults[entry.itemId] = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Text('密码体检',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
      content: SizedBox(
        width: 480,
        height: 420,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Text(_error!,
                        style: const TextStyle(color: AppTheme.error)))
                : _buildReport(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }

  Widget _buildReport() {
    final total =
        _weak.length + _duplicates.length + _aged.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.successSubtle,
            borderRadius: BorderRadius.circular(6),
          ),
          child: const Row(
            children: [
              Icon(Icons.offline_pin_outlined,
                  size: 14, color: AppTheme.success),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  '纯本地体检，无网络请求。泄露检测需逐条手动触发（k-匿名）。',
                  style: TextStyle(color: AppTheme.success, fontSize: 11),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text(
          total == 0
              ? '未发现问题 🎉'
              : '发现 $_weak.length 个弱密码 · ${_duplicates.length} 组重复 · ${_aged.length} 个超期未换',
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView(
            children: [
              if (_weak.isNotEmpty) _section('弱密码', AppTheme.error),
              for (final w in _weak) _weakTile(w),
              if (_duplicates.isNotEmpty)
                _section('重复密码', AppTheme.warning),
              for (final d in _duplicates) _dupTile(d),
              if (_aged.isNotEmpty) _section('超期未更换', AppTheme.warning),
              for (final a in _aged) _agedTile(a),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section(String label, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }

  VaultItem? _itemById(String id) {
    try {
      return widget.store.items.firstWhere((e) => e.id == id);
    } catch (_) {
      return null;
    }
  }

  Widget _weakTile(WeakPasswordEntry w) {
    final breach = _breachResults[w.itemId];
    return _tile(
      title: w.title,
      subtitle: '强度 ${w.score}/100',
      trailing: breach == null
          ? const Text('检测失败',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 11))
          : breach == -1
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : breach == 1
                  ? const Text('已泄露!',
                      style: TextStyle(
                          color: AppTheme.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w600))
                  : TextButton(
                      onPressed: () => _checkBreach(w),
                      child: const Text('检查泄露',
                          style: TextStyle(fontSize: 11)),
                    ),
      onTap: () {
        final item = _itemById(w.itemId);
        if (item != null) widget.onNavigateToItem(item);
      },
    );
  }

  Widget _dupTile(DuplicateGroup d) {
    return _tile(
      title: d.titles.join('、'),
      subtitle: '${d.itemIds.length} 个条目共用同一密码',
      onTap: () {
        final item = _itemById(d.itemIds.first);
        if (item != null) widget.onNavigateToItem(item);
      },
    );
  }

  Widget _agedTile(VaultItem a) {
    final days = DateTime.now().difference(a.passwordUpdatedAt).inDays;
    return _tile(
      title: a.title,
      subtitle: '$days 天未更换',
      onTap: () => widget.onNavigateToItem(a),
    );
  }

  Widget _tile({
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: AppTheme.bgInput,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: AppTheme.textPrimary, fontSize: 13),
                      overflow: TextOverflow.ellipsis),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppTheme.textTertiary, fontSize: 11)),
                ],
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }
}
