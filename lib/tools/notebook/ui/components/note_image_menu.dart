import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

import 'note_image_block_component.dart';

/// 图片块浮条。
///
/// [state] 的类型是自己的 `NoteImageBlockComponentWidgetState`（不再是包内那个
/// `ImageBlockComponentWidgetState`）——见 `note_image_block_component.dart`
/// 顶部的 typedef 说明。
Widget buildNoteImageMenu(
  BuildContext context,
  Node node,
  NoteImageBlockComponentWidgetState state,
) {
  final editorState = state.editorState;
  final attributes = node.attributes;
  final src = attributes[ImageBlockKeys.url]?.toString() ?? '';

  void setWidth(double percentage) {
    // 基准是**编辑器内容区**宽度，不是整窗宽度——否则「点 100%」会比内容区
    // 宽（窗口还有活动栏与内容留白），也和三路之外的拖拽口径不一致。
    //
    // 下限 100 兜的是窄窗口：25% 若被算成不足 100px，图片会被压成看不清的
    // 细条。上界取内容区宽度，超出会被容器裁掉。
    final contentWidth = editorContentWidth(context);
    final newWidth = (contentWidth * percentage).clamp(100.0, contentWidth);
    final transaction = editorState.transaction
      ..updateNode(node, {
        ImageBlockKeys.width: newWidth,
      });
    editorState.apply(transaction);
  }

  void setAlign(String align) {
    final transaction = editorState.transaction
      ..updateNode(node, {
        ImageBlockKeys.align: align,
      });
    editorState.apply(transaction);
  }

  void copyImage() {
    if (src.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: src));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制图片路径到剪贴板'), duration: Duration(seconds: 1)),
      );
    }
  }

  void deleteImage() {
    final transaction = editorState.transaction..deleteNode(node);
    editorState.apply(transaction);
  }

  return Positioned(
    top: 8,
    right: 8,
    child: Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xEE1E293B),
          borderRadius: BorderRadius.circular(6),
          boxShadow: const [
            BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _presetBtn('25%', () => setWidth(0.25)),
            _presetBtn('50%', () => setWidth(0.50)),
            _presetBtn('75%', () => setWidth(0.75)),
            _presetBtn('100%', () => setWidth(1.0)),
            const SizedBox(width: 4),
            Container(width: 1, height: 14, color: const Color(0xFF475569)),
            const SizedBox(width: 4),
            _iconBtn(Icons.format_align_left, '居左', () => setAlign('left')),
            _iconBtn(Icons.format_align_center, '居中', () => setAlign('center')),
            _iconBtn(Icons.format_align_right, '居右', () => setAlign('right')),
            const SizedBox(width: 4),
            Container(width: 1, height: 14, color: const Color(0xFF475569)),
            const SizedBox(width: 4),
            _iconBtn(Icons.copy_rounded, '复制路径', copyImage),
            _iconBtn(Icons.delete_outline_rounded, '删除图片', deleteImage, color: Colors.redAccent),
          ],
        ),
      ),
    ),
  );
}

Widget _presetBtn(String label, VoidCallback onTap) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(3),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(
        label,
        style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold),
      ),
    ),
  );
}

Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap, {Color color = Colors.white70}) {
  return Tooltip(
    message: tooltip,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(3),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Icon(icon, size: 14, color: color),
      ),
    ),
  );
}
