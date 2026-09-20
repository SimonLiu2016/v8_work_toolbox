import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../note_database.dart';
import '../note_store.dart';
import 'notebook_light_scope.dart';
import 'related_notes_section.dart';

/// 元数据栏资产 chip 的摘要文案。
///
/// 有资产数据时优先显示品类，其次显示到期倒计时；两者皆无（理论上不存在，
/// 只要有任一日期就算有数据）则返回 `null`，由调用方回落到裸「资产」。
String? assetChipLabel(Note note) {
  final cat = note.assetCategory;
  if (cat != null && cat.trim().isNotEmpty) return cat.trim();

  final expiry = note.assetExpiryDate;
  if (expiry != null) {
    final days = expiry.difference(DateTime.now()).inDays;
    if (days < 0) return '已过期';
    if (days == 0) return '今天到期';
    return '$days 天';
  }

  final service = note.assetServiceUntil;
  if (service != null) {
    final days = service.difference(DateTime.now()).inDays;
    if (days < 0) return '服务期已过';
    if (days == 0) return '今天到期';
    return '服务期 $days 天';
  }

  return null;
}

/// 该笔记是否已登记任何资产字段。
bool hasAssetData(Note note) =>
    assetChipLabel(note) != null ||
    note.assetPurchaseDate != null ||
    note.assetServiceUntil != null ||
    note.assetExpiryDate != null;

/// 元数据栏的「资产 / 凭证」chip。
///
/// 有资产数据时 chip 显示品类或到期倒计时，无数据时显示裸「资产」——
/// 不用会让用户误解该笔记是否有资产数据的徽标。
class AssetChipButton extends StatelessWidget {
  const AssetChipButton({super.key, required this.note, this.onTap});

  final Note note;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final label = assetChipLabel(note);
    return MetaChip(
      icon: Icons.inventory_2_outlined,
      label: label == null ? '资产' : '资产·$label',
      tooltip: '资产 / 凭证：品类、购买日、服务期、到期日、凭证标记',
      onTap: onTap,
    );
  }
}

/// 打开「资产 / 凭证」编辑弹窗（元数据栏资产 chip 的载体）。
///
/// 内容即 [AssetFieldsPanel]，去掉内联形态的折叠态——弹窗本身就是展开态。
/// 对外只通过 [onChanged] 通知外部刷新。
Future<void> showAssetDialog(
  BuildContext context, {
  required Note note,
  VoidCallback? onChanged,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => NotebookLightScope(
      child: AlertDialog(
        backgroundColor: NotebookLightScope.surface,
        title: const Text(
          '资产 / 凭证',
          style: TextStyle(fontSize: 15, color: NotebookLightScope.textPrimary),
        ),
        content: AssetFieldsPanel(note: note, onChanged: onChanged),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '完成',
              style: TextStyle(color: NotebookLightScope.accent),
            ),
          ),
        ],
      ),
    ),
  );
}

/// 资产字段编辑面板（阶段一）。
///
/// 编辑品类 / 购买日 / 服务期至 / 到期日，并可将附件标记为"凭证"
/// （供 RAG 命中后指引用户定位凭证）。改动即时落库，无需额外保存按钮。
///
/// **必须包在 [NotebookLightScope] 内**（[showAssetDialog] 已包），否则输入框
/// 会被全局暗色填充盖住。
class AssetFieldsPanel extends StatefulWidget {
  const AssetFieldsPanel({super.key, required this.note, this.onChanged});

  final Note note;
  final VoidCallback? onChanged;

  @override
  State<AssetFieldsPanel> createState() => _AssetFieldsPanelState();
}

class _AssetFieldsPanelState extends State<AssetFieldsPanel> {
  // 浅色面板调色板统一取自 [NotebookLightScope]，避免各面板各自写字面量。
  static const _titleColor = NotebookLightScope.textPrimary;
  static const _subColor = NotebookLightScope.textSecondary;
  static const _borderColor = NotebookLightScope.border;
  static const _accent = NotebookLightScope.accent;

  late TextEditingController _categoryCtrl;
  bool _saving = false;
  List<Attachment> _attachments = const [];

  @override
  void initState() {
    super.initState();
    _categoryCtrl = TextEditingController(
      text: widget.note.assetCategory ?? '',
    );
    _loadAttachments();
  }

  @override
  void didUpdateWidget(covariant AssetFieldsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id != widget.note.id) {
      _categoryCtrl.text = widget.note.assetCategory ?? '';
      _loadAttachments();
    }
  }

  @override
  void dispose() {
    _categoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAttachments() async {
    try {
      final list = await NoteStore.instance.db.attachmentsForNote(
        widget.note.id,
      );
      if (mounted) setState(() => _attachments = list);
    } catch (_) {}
  }

  Future<void> _save({
    String? category,
    DateTime? purchaseDate,
    DateTime? serviceUntil,
    DateTime? expiryDate,
    bool clearCategory = false,
    bool clearPurchase = false,
    bool clearService = false,
    bool clearExpiry = false,
  }) async {
    setState(() => _saving = true);
    try {
      await NoteStore.instance.updateAssetFields(
        widget.note.id,
        assetCategory: clearCategory
            ? const Value(null)
            : (category != null ? Value(category) : const Value.absent()),
        assetPurchaseDate: clearPurchase
            ? const Value(null)
            : (purchaseDate != null
                  ? Value(purchaseDate)
                  : const Value.absent()),
        assetServiceUntil: clearService
            ? const Value(null)
            : (serviceUntil != null
                  ? Value(serviceUntil)
                  : const Value.absent()),
        assetExpiryDate: clearExpiry
            ? const Value(null)
            : (expiryDate != null ? Value(expiryDate) : const Value.absent()),
      );
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('资产字段保存失败: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<DateTime?> _pickDate(DateTime? initial) async {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      initialDate: initial ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 50),
    );
  }

  String _fmt(DateTime? d) => d == null
      ? '未设置'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final n = widget.note;

    return SizedBox(
      width: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(
            label: '品类',
            child: TextField(
              controller: _categoryCtrl,
              style: const TextStyle(fontSize: 13, color: _titleColor),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '如 延保服务 / 会员 / 保险',
                hintStyle: TextStyle(fontSize: 12, color: _subColor),
              ),
              onSubmitted: (v) => _save(
                category: v.trim().isEmpty ? null : v.trim(),
                clearCategory: v.trim().isEmpty,
              ),
            ),
          ),
          const SizedBox(height: 6),
          _dateRow('购买日', n.assetPurchaseDate, () async {
            final d = await _pickDate(n.assetPurchaseDate);
            if (d != null) await _save(purchaseDate: d);
          }, () => _save(clearPurchase: true)),
          _dateRow('服务期至', n.assetServiceUntil, () async {
            final d = await _pickDate(n.assetServiceUntil);
            if (d != null) await _save(serviceUntil: d);
          }, () => _save(clearService: true)),
          _dateRow('到期日', n.assetExpiryDate, () async {
            final d = await _pickDate(n.assetExpiryDate);
            if (d != null) await _save(expiryDate: d);
          }, () => _save(clearExpiry: true)),
          if (_attachments.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              '凭证附件',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _subColor,
              ),
            ),
            const SizedBox(height: 4),
            ..._attachments.map(_credentialRow),
          ],
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }

  Widget _field({required String label, required Widget child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: const TextStyle(fontSize: 12, color: _subColor),
          ),
        ),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: NotebookLightScope.surfaceMuted,
              border: Border.all(color: _borderColor),
              borderRadius: BorderRadius.circular(6),
            ),
            child: child,
          ),
        ),
      ],
    );
  }

  Widget _dateRow(
    String label,
    DateTime? value,
    VoidCallback onPick,
    VoidCallback onClear,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: _subColor),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: onPick,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: NotebookLightScope.surfaceMuted,
                  border: Border.all(color: _borderColor),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _fmt(value),
                  style: TextStyle(
                    fontSize: 12,
                    color: value == null ? _subColor : _titleColor,
                  ),
                ),
              ),
            ),
          ),
          if (value != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 14, color: _subColor),
              tooltip: '清除',
              onPressed: onClear,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            ),
        ],
      ),
    );
  }

  Widget _credentialRow(Attachment att) {
    return Row(
      children: [
        Checkbox(
          value: att.isCredential,
          activeColor: _accent,
          visualDensity: VisualDensity.compact,
          onChanged: (v) async {
            await NoteStore.instance.flagAttachmentCredential(
              att.id,
              v ?? false,
            );
            await _loadAttachments();
            widget.onChanged?.call();
          },
        ),
        Expanded(
          child: Text(
            att.filename ?? att.localPath.split('/').last,
            style: const TextStyle(fontSize: 11, color: _titleColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
