import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../crypto/dek_backup.dart';
import '../crypto/kek_manager.dart';
import '../services/clipboard_service.dart';
import '../vault_store.dart';

/// 设置面板（spec：剪贴板清空延时配置、DEK 备份/恢复、立即锁定）
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key, required this.store});

  final VaultStore store;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  final _clipboard = ClipboardHygieneService.instance;
  String? _message;
  bool _messageIsError = false;
  DekSource? _dekSource;

  @override
  void initState() {
    super.initState();
    _loadDekSource();
  }

  Future<void> _loadDekSource() async {
    try {
      await KekManager().getOrCreateDek();
      if (mounted) setState(() => _dekSource = KekManager().source);
    } catch (_) {
      if (mounted) setState(() => _dekSource = DekSource.none);
    }
  }

  String _dekSourceLabel(DekSource source) {
    switch (source) {
      case DekSource.keychain:
        return 'macOS 钥匙串（系统级保护）';
      case DekSource.file:
        return '本地文件 0600 权限（应用未签名，钥匙串不可写）';
      case DekSource.ephemeral:
        return '内存（本次会话，不持久化）';
      case DekSource.none:
        return '未初始化';
    }
  }

  void _notify(String msg, {bool isError = false}) {
    setState(() {
      _message = msg;
      _messageIsError = isError;
    });
  }

  Future<void> _exportDek() async {
    final passphrase = await _askPassphrase(
      title: '导出密钥备份',
      confirm: true,
      hint: '设置备份口令（至少 8 字符，恢复时需要）',
    );
    if (passphrase == null) return;

    try {
      final dek = await KekManager().getDek();
      final backup = await DekBackup().exportDek(dek, passphrase);

      final path = await FilePicker.platform.saveFile(
        dialogTitle: '选择备份保存位置',
        fileName: 'v8-dek-backup.bin',
      );
      if (path == null) return;
      await File(path).writeAsBytes(backup, flush: true);
      _notify('备份已导出到 $path');
    } on DekUnavailableException catch (e) {
      _notify(e.message, isError: true);
    } catch (e) {
      _notify('导出失败：$e', isError: true);
    }
  }

  Future<void> _restoreDek() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        dialogTitle: '选择 DEK 备份文件',
        type: FileType.any,
      );
      final path = picked?.files.single.path;
      if (path == null) return;

      final passphrase = await _askPassphrase(
        title: '恢复密钥备份',
        confirm: false,
        hint: '输入导出时设置的备份口令',
      );
      if (passphrase == null) return;

      final bytes = await File(path).readAsBytes();
      final dek = await DekBackup().importDek(bytes, passphrase);
      await KekManager().importDek(dek);

      // 校验 vault 可读
      await widget.store.load();
      _notify('密钥已恢复，密码库可正常读取');
    } on DekBackupException catch (e) {
      _notify(e.message, isError: true);
    } catch (e) {
      _notify('恢复失败：$e', isError: true);
    }
  }

  Future<String?> _askPassphrase({
    required String title,
    required bool confirm,
    required String hint,
  }) async {
    final controller = TextEditingController();
    final confirmController = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: AppTheme.bgCard,
              title: Text(title,
                  style: const TextStyle(
                      color: AppTheme.textPrimary, fontSize: 15)),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(hint,
                        style: const TextStyle(
                            color: AppTheme.textSecondary, fontSize: 12)),
                    const SizedBox(height: 12),
                    _passField(controller, '口令'),
                    if (confirm) ...[
                      const SizedBox(height: 10),
                      _passField(confirmController, '再次输入'),
                    ],
                    if (error != null) ...[
                      const SizedBox(height: 8),
                      Text(error!,
                          style: const TextStyle(
                              color: AppTheme.error, fontSize: 11)),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  style:
                      FilledButton.styleFrom(backgroundColor: AppTheme.accent),
                  onPressed: () {
                    final p = controller.text;
                    if (p.length < 8) {
                      setDialogState(() => error = '口令至少 8 个字符');
                      return;
                    }
                    if (confirm && p != confirmController.text) {
                      setDialogState(() => error = '两次输入不一致');
                      return;
                    }
                    Navigator.of(ctx).pop(p);
                  },
                  child: const Text('确定'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
    confirmController.dispose();
    return result;
  }

  Widget _passField(TextEditingController c, String label) {
    return TextField(
      controller: c,
      obscureText: true,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
        filled: true,
        fillColor: AppTheme.bgInput,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: const Text('设置',
          style: TextStyle(color: AppTheme.textPrimary, fontSize: 16)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('剪贴板自动清空',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final s in ClipboardHygieneService.delayOptions)
                  ChoiceChip(
                    label: Text(s == 0 ? '禁用' : '$s 秒',
                        style: const TextStyle(fontSize: 12)),
                    selected: _clipboard.delaySeconds == s,
                    selectedColor: AppTheme.accentSubtle,
                    onSelected: (_) {
                      setState(() => _clipboard.setDelaySeconds(s));
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
            const Text('密钥来源',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              _dekSource == null ? '检测中…' : _dekSourceLabel(_dekSource!),
              style: TextStyle(
                color: _dekSource == DekSource.keychain
                    ? AppTheme.success
                    : AppTheme.warning,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 20),
            const Text('密钥备份（跨机器迁移）',
                style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Row(
              children: [
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.borderStrong),
                  ),
                  onPressed: _exportDek,
                  icon: const Icon(Icons.upload_rounded, size: 16),
                  label: const Text('导出密钥备份',
                      style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textSecondary,
                    side: const BorderSide(color: AppTheme.borderStrong),
                  ),
                  onPressed: _restoreDek,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('恢复密钥备份',
                      style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              '备份文件经口令加密，不含密码明文。口令不存储、不可恢复，请妥善记忆。',
              style: TextStyle(color: AppTheme.textTertiary, fontSize: 11),
            ),
            if (_message != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _messageIsError
                      ? AppTheme.errorSubtle
                      : AppTheme.successSubtle,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _message!,
                  style: TextStyle(
                    color: _messageIsError
                        ? AppTheme.error
                        : AppTheme.success,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
