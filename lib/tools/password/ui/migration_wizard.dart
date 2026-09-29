import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../migration/legacy_importer.dart';
import '../migration/migration_service.dart';

/// 迁移向导（spec：Legacy migration wizard）
///
/// 检测到 legacy `.secrets.dat` 时全屏展示：
/// 预览 keyId 列表（不含明文）→ 执行三段式迁移 → 展示结果。
class MigrationWizard extends StatefulWidget {
  const MigrationWizard({
    super.key,
    required this.onComplete,
    required this.onSkip,
  });

  final VoidCallback onComplete;
  final VoidCallback onSkip;

  @override
  State<MigrationWizard> createState() => _MigrationWizardState();
}

class _MigrationWizardState extends State<MigrationWizard> {
  final MigrationService _service = MigrationService();

  List<String>? _keys;
  bool _migrating = false;
  LegacyMigrationResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    try {
      final keys = await _service.previewLegacyKeys();
      if (mounted) setState(() => _keys = keys);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _runMigration() async {
    setState(() {
      _migrating = true;
      _error = null;
    });
    try {
      final result = await _service.migrate();
      if (mounted) {
        setState(() {
          _result = result;
          _migrating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _migrating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 520,
        padding: EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: context.bgCard,
          borderRadius: BorderRadius.circular(12),
        ),
        child: _result != null ? _buildResult() : _buildPreview(),
      ),
    );
  }

  Widget _buildPreview() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.upgrade_rounded, color: context.accentText, size: 28),
            SizedBox(width: 12),
            Text(
              '凭证存储升级',
              style: TextStyle(
                color: context.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        SizedBox(height: 16),
        Text(
          '检测到旧版凭证存储。旧格式使用弱混淆保护，本次升级将其迁移到 AES-256-GCM 加密存储（密钥由 macOS 钥匙串托管）。',
          style: TextStyle(color: context.textSecondary, fontSize: 13),
        ),
        SizedBox(height: 16),
        if (_keys == null && _error == null)
          Center(child: CircularProgressIndicator())
        else if (_error != null)
          Text(_error!,
              style: TextStyle(color: context.errorText, fontSize: 12))
        else ...[
          Text(
            '将迁移 ${_keys!.length} 条凭证：',
            style: TextStyle(color: context.textPrimary, fontSize: 13),
          ),
          SizedBox(height: 8),
          Container(
            constraints: BoxConstraints(maxHeight: 160),
            padding: EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.bgInput,
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final key in _keys!)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      '• $key',
                      style: TextStyle(
                          color: context.textSecondary,
                          fontSize: 12,
                          fontFamily: 'monospace'),
                    ),
                  ),
              ],
            ),
          ),
        ],
        SizedBox(height: 12),
        Text(
          '迁移成功后旧文件将被删除。若迁移失败，旧文件保留可重试。',
          style: TextStyle(color: context.textTertiary, fontSize: 11),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton(
              onPressed: widget.onSkip,
              child: const Text('稍后迁移'),
            ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.accentSolid),
              onPressed:
                  _migrating || _keys == null || _keys!.isEmpty
                      ? null
                      : _runMigration,
              child: Text(_migrating ? '迁移中…' : '立即迁移'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildResult() {
    final result = _result!;
    final ok = !result.hasFailures;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.error_outline,
          color: ok ? context.successText : context.errorText,
          size: 48,
        ),
        SizedBox(height: 16),
        Text(
          ok ? '迁移完成' : '迁移部分失败',
          style: TextStyle(
            color: context.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        SizedBox(height: 8),
        Text(
          '成功迁移 ${result.migratedCount} 条凭证'
          '${result.legacyFileDeleted ? '，旧文件已删除' : ''}',
          style: TextStyle(color: context.textSecondary, fontSize: 13),
        ),
        if (result.hasFailures) ...[
          const SizedBox(height: 12),
          Container(
            constraints: const BoxConstraints(maxHeight: 140),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: context.errorText.withValues(alpha: 0x1F / 255),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final e in result.failures.entries)
                  Text(
                    '${e.key}: ${e.value}',
                    style:
                        TextStyle(color: context.errorText, fontSize: 11),
                  ),
              ],
            ),
          ),
          SizedBox(height: 8),
          Text(
            '旧文件已保留，可重试迁移。',
            style: TextStyle(color: context.textTertiary, fontSize: 11),
          ),
        ],
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (result.hasFailures)
              TextButton(
                onPressed: () {
                  setState(() {
                    _result = null;
                  });
                  _loadPreview();
                },
                child: const Text('重试'),
              ),
            const SizedBox(width: 12),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: context.accentSolid),
              onPressed: widget.onComplete,
              child: const Text('进入密码工具'),
            ),
          ],
        ),
      ],
    );
  }
}
