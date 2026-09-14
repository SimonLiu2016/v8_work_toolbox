import 'dart:async';

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../services/clipboard_service.dart';
import '../services/totp_service.dart';
import '../vault_models.dart';
import '../vault_store.dart';
import 'totp_badge.dart';

/// 条目编辑对话框（新建 / 编辑 login、note、totp 三类型）
class ItemEditorDialog extends StatefulWidget {
  const ItemEditorDialog({
    super.key,
    required this.store,
    this.existing,
    required this.onSaved,
  });

  final VaultStore store;
  final VaultItem? existing;
  final ValueChanged<VaultItem> onSaved;

  @override
  State<ItemEditorDialog> createState() => _ItemEditorDialogState();
}

class _ItemEditorDialogState extends State<ItemEditorDialog> {
  late VaultEntryType _type;
  late final TextEditingController _title;
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _secret;
  late final TextEditingController _totpSeed;
  late final TextEditingController _tags;
  late final TextEditingController _notes;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _type = e?.type ?? VaultEntryType.login;
    _title = TextEditingController(text: e?.title ?? '');
    _url = TextEditingController(text: e?.url ?? '');
    _username = TextEditingController(text: e?.username ?? '');
    _secret = TextEditingController();
    _totpSeed = TextEditingController();
    _tags = TextEditingController(text: e?.tags.join(', ') ?? '');
    _notes = TextEditingController(text: e?.notes ?? '');
    if (e != null) {
      _loadExistingSecret();
    }
  }

  Future<void> _loadExistingSecret() async {
    try {
      final secret = await widget.store.readSecret(widget.existing!.id);
      if (mounted) {
        _secret.text = secret.secret;
        _totpSeed.text = secret.totpSeed;
      }
    } catch (_) {
      // DEK 不可用时留空，保存时会报错提示
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _url.dispose();
    _username.dispose();
    _secret.dispose();
    _totpSeed.dispose();
    _tags.dispose();
    _notes.dispose();
    super.dispose();
  }

  List<String> _parseTags() {
    return _tags.text
        .split(RegExp(r'[,，]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  void _onSecretChanged(String value) {
    // otpauth:// URI 粘贴自动填充
    if (value.startsWith('otpauth://')) {
      final data = TotpService.parseOtpauthUri(value);
      if (data != null && mounted) {
        setState(() {
          _type = VaultEntryType.totp;
          _totpSeed.text = data.secret;
          if (_title.text.isEmpty && data.issuer.isNotEmpty) {
            _title.text = data.issuer;
          }
          if (_username.text.isEmpty && data.account.isNotEmpty) {
            _username.text = data.account;
          }
          _secret.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已识别 otpauth URI 并自动填充 TOTP 字段')),
        );
      }
    }
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = '标题不能为空');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final tags = _parseTags();
      VaultItem result;
      final existing = widget.existing;
      if (existing == null) {
        result = await widget.store.create(
          type: _type,
          title: _title.text.trim(),
          url: _url.text.trim(),
          username: _username.text.trim(),
          secret: _secret.text,
          totpSeed: _type == VaultEntryType.totp ? _totpSeed.text.trim() : '',
          tags: tags,
          notes: _notes.text,
        );
      } else {
        result = await widget.store.update(
          existing.id,
          title: _title.text.trim(),
          url: _url.text.trim(),
          username: _username.text.trim(),
          tags: tags,
          notes: _notes.text,
          secret: _secret.text.isNotEmpty ? _secret.text : null,
          totpSeed: _type == VaultEntryType.totp ? _totpSeed.text.trim() : null,
        );
      }
      if (mounted) {
        widget.onSaved(result);
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '保存失败：$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      backgroundColor: AppTheme.bgCard,
      title: Text(
        isEdit ? '编辑条目' : '新建条目',
        style: const TextStyle(color: AppTheme.textPrimary, fontSize: 16),
      ),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _typeSelector(),
              const SizedBox(height: 16),
              _field(_title, '标题 *'),
              const SizedBox(height: 12),
              if (_type == VaultEntryType.login) ...[
                _field(_url, '网址'),
                const SizedBox(height: 12),
                _field(_username, '用户名'),
                const SizedBox(height: 12),
                _field(_secret, '密码', obscure: true, onChanged: _onSecretChanged),
                const SizedBox(height: 12),
              ],
              if (_type == VaultEntryType.totp) ...[
                _field(_username, '账户名'),
                const SizedBox(height: 12),
                _field(_totpSeed, 'TOTP Seed（Base32）或 otpauth:// URI',
                    onChanged: _onSecretChanged),
                const SizedBox(height: 12),
              ],
              if (_type == VaultEntryType.note) ...[
                _field(_secret, '内容', obscure: true, maxLines: 5),
                const SizedBox(height: 12),
              ],
              _field(_tags, '标签（逗号分隔）'),
              const SizedBox(height: 12),
              _field(_notes, '备注', maxLines: 3),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!,
                    style:
                        const TextStyle(color: AppTheme.error, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
          onPressed: _saving ? null : _save,
          child: Text(_saving ? '保存中…' : '保存'),
        ),
      ],
    );
  }

  Widget _typeSelector() {
    return Row(
      children: [
        for (final (type, label, icon) in [
          (VaultEntryType.login, '登录', Icons.key_rounded),
          (VaultEntryType.note, '笔记', Icons.sticky_note_2_outlined),
          (VaultEntryType.totp, 'TOTP', Icons.timer_outlined),
        ])
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: ChoiceChip(
                avatar: Icon(icon,
                    size: 16,
                    color: _type == type
                        ? Colors.white
                        : AppTheme.textSecondary),
                label: Text(label),
                selected: _type == type,
                selectedColor: AppTheme.accent,
                backgroundColor: AppTheme.bgInput,
                labelStyle: TextStyle(
                  color:
                      _type == type ? Colors.white : AppTheme.textSecondary,
                  fontSize: 12,
                ),
                onSelected: (_) => setState(() => _type = type),
              ),
            ),
          ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool obscure = false,
    int maxLines = 1,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure && maxLines == 1,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
      decoration: InputDecoration(
        labelText: label,
        labelStyle:
            const TextStyle(color: AppTheme.textTertiary, fontSize: 12),
        filled: true,
        fillColor: AppTheme.bgInput,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

/// 条目详情视图（右侧面板）：掩码 secret、复制、TOTP 徽章、编辑/删除
class ItemDetailView extends StatefulWidget {
  const ItemDetailView({
    super.key,
    required this.store,
    required this.item,
    required this.onEdit,
    required this.onDelete,
  });

  final VaultStore store;
  final VaultItem item;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  State<ItemDetailView> createState() => _ItemDetailViewState();
}

class _ItemDetailViewState extends State<ItemDetailView> {
  VaultSecret? _secret;
  bool _revealed = false;
  String? _error;
  final _clipboard = ClipboardHygieneService.instance;

  @override
  void initState() {
    super.initState();
    _loadSecret();
  }

  Future<void> _loadSecret() async {
    try {
      final secret = await widget.store.readSecret(widget.item.id);
      if (mounted) setState(() => _secret = secret);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _copy(String value, String what) async {
    await _clipboard.copySecret(value);
    if (mounted) {
      final delay = _clipboard.delaySeconds;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            delay > 0 ? '$what已复制，$delay 秒后自动清空剪贴板' : '$what已复制',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title.isEmpty ? '（无标题）' : item.title,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined,
                    color: AppTheme.textSecondary, size: 20),
                tooltip: '编辑',
                onPressed: widget.onEdit,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline,
                    color: AppTheme.error, size: 20),
                tooltip: '删除',
                onPressed: widget.onDelete,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (item.url.isNotEmpty) _row('网址', item.url),
          if (item.username.isNotEmpty)
            _row('用户名', item.username,
                onCopy: () => _copy(item.username, '用户名')),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(_error!,
                  style: const TextStyle(color: AppTheme.error, fontSize: 12)),
            ),
          if (_secret != null) ...[
            if (item.type != VaultEntryType.totp && _secret!.secret.isNotEmpty)
              _secretRow(
                item.type == VaultEntryType.note ? '内容' : '密码',
                _secret!.secret,
              ),
            if (item.type == VaultEntryType.totp &&
                _secret!.totpSeed.isNotEmpty)
              TotpBadge(seed: _secret!.totpSeed),
          ],
          if (item.tags.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 6,
              children: [
                for (final tag in item.tags)
                  Chip(
                    label: Text(tag, style: const TextStyle(fontSize: 11)),
                    backgroundColor: AppTheme.accentSubtle,
                    side: BorderSide.none,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
          if (item.notes.isNotEmpty) ...[
            const SizedBox(height: 16),
            const Text('备注',
                style:
                    TextStyle(color: AppTheme.textTertiary, fontSize: 11)),
            const SizedBox(height: 4),
            Text(item.notes,
                style: const TextStyle(
                    color: AppTheme.textSecondary, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          Text(
            '更新于 ${_fmt(item.updatedAt)} · 密码修改于 ${_fmt(item.passwordUpdatedAt)}',
            style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Widget _row(String label, String value, {VoidCallback? onCopy}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style:
                    const TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppTheme.textPrimary, fontSize: 13)),
          ),
          if (onCopy != null)
            InkWell(
              onTap: onCopy,
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.copy_rounded,
                    size: 14, color: AppTheme.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _secretRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(label,
                style:
                    const TextStyle(color: AppTheme.textTertiary, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              _revealed ? value : '●' * (value.length.clamp(6, 16)),
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontFamily: _revealed ? null : 'monospace',
              ),
            ),
          ),
          InkWell(
            onTap: () => setState(() => _revealed = !_revealed),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                _revealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 14,
                color: AppTheme.textTertiary,
              ),
            ),
          ),
          InkWell(
            onTap: () => _copy(value, label),
            child: const Padding(
              padding: EdgeInsets.all(4),
              child: Icon(Icons.copy_rounded,
                  size: 14, color: AppTheme.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}
