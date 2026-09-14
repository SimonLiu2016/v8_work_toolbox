import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

Widget buildNoteImageMenu(
  BuildContext context,
  Node node,
  ImageBlockComponentWidgetState state,
) {
  final editorState = state.editorState;
  final attributes = node.attributes;
  final src = attributes[ImageBlockKeys.url]?.toString() ?? '';

  void setWidth(double percentage) {
    final mediaWidth = MediaQuery.of(context).size.width;
    final newWidth = (mediaWidth * percentage).clamp(100.0, mediaWidth);
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
