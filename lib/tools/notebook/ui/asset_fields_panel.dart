import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';

import '../note_database.dart';
import '../note_store.dart';

/// 资产字段编辑面板（阶段一）。
///
/// 可折叠，默认对无资产数据的笔记折叠。编辑品类 / 购买日 / 服务期 / 到期日，
/// 并可将附件标记为"凭证"（供 RAG 命中后指引用户定位凭证）。
class AssetFieldsPanel extends StatefulWidget {
  const AssetFieldsPanel({
    super.key,
    required this.note,
    required this.onChanged,
  });

  final Note note;
  final VoidCallback onChanged;

  @override
  State<AssetFieldsPanel> createState() => _AssetFieldsPanelState();
}

class _AssetFieldsPanelState extends State<AssetFieldsPanel> {
  static const _titleColor = Color(0xFF0F172A);
  static const _subColor = Color(0xFF64748B);
  static const _borderColor = Color(0xFFE5E7EB);
  static const _accent = Color(0xFF3B82F6);

  late bool _expanded;
  late TextEditingController _categoryCtrl;
  bool _saving = false;
  List<Attachment> _attachments = const [];

  @override
  void initState() {
    super.initState();
    _categoryCtrl = TextEditingController(text: widget.note.assetCategory ?? '');
    // 有资产数据的笔记默认展开，普通笔记折叠。
    _expanded = _hasAssetData(widget.note);
    _loadAttachments();
  }

  @override
  void didUpdateWidget(covariant AssetFieldsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.id != widget.note.id) {
      _categoryCtrl.text = widget.note.assetCategory ?? '';
      _expanded = _hasAssetData(widget.note);
      _loadAttachments();
    }
  }

  @override
  void dispose() {
    _categoryCtrl.dispose();
    super.dispose();
  }

  bool _hasAssetData(Note n) =>
      (n.assetCategory != null && n.assetCategory!.isNotEmpty) ||
      n.assetPurchaseDate != null ||
      n.assetServiceUntil != null ||
      n.assetExpiryDate != null;

  Future<void> _loadAttachments() async {
    try {
      final list = await NoteStore.instance.db.attachmentsForNote(widget.note.id);
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
            : (purchaseDate != null ? Value(purchaseDate) : const Value.absent()),
        assetServiceUntil: clearService
            ? const Value(null)
            : (serviceUntil != null ? Value(serviceUntil) : const Value.absent()),
        assetExpiryDate: clearExpiry
            ? const Value(null)
            : (expiryDate != null ? Value(expiryDate) : const Value.absent()),
      );
      widget.onChanged();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('资产字段保存失败: $e')),
        );
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

  String _fmt(DateTime? d) =>
      d == null ? '未设置' : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String? _expiryHint(DateTime? expiry) {
    if (expiry == null) return null;
    final days = expiry.difference(DateTime.now()).inDays;
    if (days < 0) return '已过期';
    if (days == 0) return '今天到期';
    return '$days 天后到期';
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.note;
    final hint = _expiryHint(n.assetExpiryDate);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: _borderColor),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header（点击折叠/展开）
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      size: 16, color: _subColor),
                  const SizedBox(width: 6),
                  const Icon(Icons.inventory_2_outlined, size: 14, color: _accent),
                  const SizedBox(width: 6),
                  const Text('资产 / 凭证',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _titleColor)),
                  if (hint != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: hint == '已过期' ? const Color(0xFFFEE2E2) : const Color(0xFFDBEAFE),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(hint,
                          style: TextStyle(
                            fontSize: 10,
                            color: hint == '已过期' ? const Color(0xFFB91C1C) : const Color(0xFF1D4ED8),
                          )),
                    ),
                  ],
                  const Spacer(),
                  if (_saving)
                    const SizedBox(
                        width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 1.5)),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1, color: _borderColor),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(
                    label: '品类',
                    child: TextField(
                      controller: _categoryCtrl,
                      style: const TextStyle(fontSize: 12, color: _titleColor),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: '如 延保服务 / 会员 / 保险',
                        hintStyle: TextStyle(fontSize: 12, color: _subColor),
                        border: InputBorder.none,
                      ),
                      onSubmitted: (v) => _save(category: v.trim().isEmpty ? null : v.trim(),
                          clearCategory: v.trim().isEmpty),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _dateRow('购买日', n.assetPurchaseDate,
                      () async {
                        final d = await _pickDate(n.assetPurchaseDate);
                        if (d != null) await _save(purchaseDate: d);
                      },
                      () => _save(clearPurchase: true)),
                  _dateRow('服务期至', n.assetServiceUntil,
                      () async {
                        final d = await _pickDate(n.assetServiceUntil);
                        if (d != null) await _save(serviceUntil: d);
                      },
                      () => _save(clearService: true)),
                  _dateRow('到期日', n.assetExpiryDate,
                      () async {
                        final d = await _pickDate(n.assetExpiryDate);
                        if (d != null) await _save(expiryDate: d);
                      },
                      () => _save(clearExpiry: true)),
                  if (_attachments.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('凭证附件',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _subColor)),
                    const SizedBox(height: 4),
                    ..._attachments.map(_credentialRow),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _field({required String label, required Widget child}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 64,
          child: Text(label, style: const TextStyle(fontSize: 12, color: _subColor)),
        ),
        Expanded(child: child),
      ],
    );
  }

  Widget _dateRow(String label, DateTime? value, VoidCallback onPick, VoidCallback onClear) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(label, style: const TextStyle(fontSize: 12, color: _subColor)),
          ),
          Expanded(
            child: InkWell(
              onTap: onPick,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                child: Text(_fmt(value),
                    style: TextStyle(
                        fontSize: 12,
                        color: value == null ? _subColor : _titleColor)),
              ),
            ),
          ),
          if (value != null)
            IconButton(
              icon: const Icon(Icons.clear, size: 13, color: _subColor),
              tooltip: '清除',
              onPressed: onClear,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
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
            await NoteStore.instance.flagAttachmentCredential(att.id, v ?? false);
            await _loadAttachments();
            widget.onChanged();
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
