import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'note_code_block_component.dart';

class NoteEditorToolbar extends StatelessWidget {
  final EditorState editorState;
  final Future<String> Function(File file, String filename)? onSaveAttachment;

  const NoteEditorToolbar({
    super.key,
    required this.editorState,
    this.onSaveAttachment,
  });

  void _formatHeading(int level) {
    final selection = editorState.selection;
    if (selection == null) return;
    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null) return;

    final path = selection.start.path;
    final delta = node.delta ?? Delta();
    final newNode = level == 0
        ? paragraphNode(delta: delta)
        : headingNode(level: level, delta: delta);

    final transaction = editorState.transaction
      ..insertNode(path, newNode)
      ..deleteNode(node);
    editorState.apply(transaction);
  }

  void _toggleAttribute(String key) {
    editorState.toggleAttribute(key);
  }

  void _insertTable() {
    final selection = editorState.selection;
    final targetPath = selection != null
        ? [selection.end.path[0] + 1]
        : [editorState.document.root.children.length];

    final tableNode = TableNode.fromList([
      [
        paragraphNode(delta: Delta()..insert('表头 1', attributes: {AppFlowyRichTextKeys.bold: true})),
        paragraphNode(delta: Delta()..insert('表头 2', attributes: {AppFlowyRichTextKeys.bold: true})),
        paragraphNode(delta: Delta()..insert('表头 3', attributes: {AppFlowyRichTextKeys.bold: true})),
      ],
      [paragraphNode(text: '内容 1'), paragraphNode(text: '内容 2'), paragraphNode(text: '内容 3')],
      [paragraphNode(text: '内容 4'), paragraphNode(text: '内容 5'), paragraphNode(text: '内容 6')],
    ]).node;

    final transaction = editorState.transaction..insertNode(targetPath, tableNode);
    editorState.apply(transaction);
  }

  void _insertCodeBlock() {
    final selection = editorState.selection;
    final targetPath = selection != null
        ? [selection.end.path[0] + 1]
        : [editorState.document.root.children.length];

    final node = codeBlockNode(code: '// 输入代码\n', language: 'dart');
    final transaction = editorState.transaction..insertNode(targetPath, node);
    editorState.apply(transaction);
  }

  Future<void> _insertImage(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      dialogTitle: '选择要插入的图片',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.first.path;
    if (path == null) return;

    String finalPath = path;
    if (onSaveAttachment != null) {
      final file = File(path);
      final filename = result.files.first.name;
      finalPath = await onSaveAttachment!(file, filename);
    }

    final selection = editorState.selection;
    final targetPath = selection != null
        ? [selection.end.path[0] + 1]
        : [editorState.document.root.children.length];

    final node = imageNode(url: finalPath);
    final transaction = editorState.transaction..insertNode(targetPath, node);
    editorState.apply(transaction);
  }

  void _insertList(String listType) {
    final selection = editorState.selection;
    if (selection == null) return;

    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null) return;

    final delta = node.delta ?? Delta();
    final path = selection.start.path;

    final attrs = <String, dynamic>{
      'delta': delta.toJson(),
    };
    if (listType == TodoListBlockKeys.type) {
      attrs[TodoListBlockKeys.checked] = false;
    }
    final newNode = Node(
      type: listType,
      attributes: attrs,
    );

    final transaction = editorState.transaction
      ..insertNode(path, newNode)
      ..deleteNode(node);
    editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // H1, H2, H3
            _toolbarBtn('正文', () => _formatHeading(0)),
            _toolbarBtn('H1', () => _formatHeading(1), bold: true),
            _toolbarBtn('H2', () => _formatHeading(2), bold: true),
            _toolbarBtn('H3', () => _formatHeading(3), bold: true),
            _divider(),

            // B, I, U, S
            _iconBtn(Icons.format_bold_rounded, '加粗 (Cmd+B)', () => _toggleAttribute(AppFlowyRichTextKeys.bold)),
            _iconBtn(Icons.format_italic_rounded, '斜体 (Cmd+I)', () => _toggleAttribute(AppFlowyRichTextKeys.italic)),
            _iconBtn(Icons.format_underlined_rounded, '下划线 (Cmd+U)', () => _toggleAttribute(AppFlowyRichTextKeys.underline)),
            _iconBtn(Icons.format_strikethrough_rounded, '删除线', () => _toggleAttribute(AppFlowyRichTextKeys.strikethrough)),
            _divider(),

            // Lists & Todos
            _iconBtn(Icons.format_list_bulleted_rounded, '无序列表', () => _insertList(BulletedListBlockKeys.type)),
            _iconBtn(Icons.format_list_numbered_rounded, '有序列表', () => _insertList(NumberedListBlockKeys.type)),
            _iconBtn(Icons.check_box_outlined, '待办清单', () => _insertList(TodoListBlockKeys.type)),
            _iconBtn(Icons.format_quote_rounded, '引用', () => _insertList(QuoteBlockKeys.type)),
            _divider(),

            // Table, Code, Image
            _actionBtn(Icons.table_chart_rounded, '插入表格', _insertTable),
            const SizedBox(width: 4),
            _actionBtn(Icons.code_rounded, '插入代码', _insertCodeBlock),
            const SizedBox(width: 4),
            _actionBtn(Icons.image_outlined, '插入图片', () => _insertImage(context)),
          ],
        ),
      ),
    );
  }

  Widget _divider() {
    return Container(
      width: 1,
      height: 18,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      color: const Color(0xFFCBD5E1),
    );
  }

  Widget _toolbarBtn(String label, VoidCallback onTap, {bool bold = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: const Color(0xFF334155),
            fontWeight: bold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 18, color: const Color(0xFF475569)),
        ),
      ),
    );
  }

  Widget _actionBtn(IconData icon, String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF2563EB)),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF2563EB), fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}
