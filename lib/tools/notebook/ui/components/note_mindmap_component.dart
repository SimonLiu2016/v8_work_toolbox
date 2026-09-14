import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

class MindMapBlockKeys {
  MindMapBlockKeys._();
  static const String type = 'mindmap';
  static const String data = 'data';
}

Node mindMapNode({required String data}) {
  return Node(
    type: MindMapBlockKeys.type,
    attributes: {
      MindMapBlockKeys.data: data,
    },
  );
}

class MindMapBlockComponentBuilder extends BlockComponentBuilder {
  MindMapBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return MindMapBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
      actionTrailingBuilder: (context, state) => actionTrailingBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => true;
}

class MindMapBlockComponentWidget extends BlockComponentStatefulWidget {
  const MindMapBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<MindMapBlockComponentWidget> createState() => _MindMapBlockComponentWidgetState();
}

class _MindMapBlockComponentWidgetState extends State<MindMapBlockComponentWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  String _title = '思维导图';
  String? _svgPath;
  Map<String, dynamic>? _tree;
  bool _showOutline = false;
  final TransformationController _transformCtrl = TransformationController();

  @override
  void initState() {
    super.initState();
    _parseData();
  }

  @override
  void didUpdateWidget(covariant MindMapBlockComponentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.node != widget.node) {
      _parseData();
    }
  }

  void _parseData() {
    final raw = widget.node.attributes[MindMapBlockKeys.data];
    if (raw is Map) {
      _title = raw['title']?.toString() ?? '思维导图';
      _svgPath = raw['svg_path']?.toString();
      _tree = raw['tree'] is Map ? (raw['tree'] as Map).cast<String, dynamic>() : null;
    } else if (raw is String) {
      try {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        _title = parsed['title'] as String? ?? parsed['name'] as String? ?? '思维导图';
        _svgPath = parsed['svg_path'] as String?;
        if (parsed.containsKey('tree') && parsed['tree'] is Map) {
          _tree = (parsed['tree'] as Map).cast<String, dynamic>();
        } else if (parsed.containsKey('mode') && parsed['mode'] == 'mindmap') {
          _tree = parsed;
        }
      } catch (_) {
        _title = '思维导图';
      }
    }
  }

  void _zoomIn() {
    _transformCtrl.value = _transformCtrl.value * Matrix4.diagonal3Values(1.25, 1.25, 1.0);
  }

  void _zoomOut() {
    _transformCtrl.value = _transformCtrl.value * Matrix4.diagonal3Values(0.8, 0.8, 1.0);
  }

  void _resetZoom() {
    _transformCtrl.value = Matrix4.identity();
  }

  Future<void> _exportSvg() async {
    if (_svgPath == null) return;
    final file = File(_svgPath!);
    if (!file.existsSync()) return;

    final output = await FilePicker.platform.saveFile(
      dialogTitle: '导出思维导图 SVG 矢量文件',
      fileName: '$_title.svg',
      type: FileType.custom,
      allowedExtensions: ['svg'],
    );
    if (output != null) {
      await file.copy(output);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已成功导出 SVG 至: $output')),
        );
      }
    }
  }

  void _deleteBlock() {
    final editorState = context.read<EditorState>();
    final transaction = editorState.transaction..deleteNode(widget.node);
    editorState.apply(transaction);
  }

  @override
  Widget build(BuildContext context) {
    final hasSvg = _svgPath != null && File(_svgPath!).existsSync();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部标头与控制栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              borderRadius: BorderRadius.vertical(top: Radius.circular(9)),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_rounded, size: 18, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: const Text('思维导图', style: TextStyle(fontSize: 10, color: Color(0xFF2563EB), fontWeight: FontWeight.w600)),
                ),
                const Spacer(),
                // 视图模式切换：矢量导图 vs 结构大纲
                Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      _tabButton('🗺️ 导图', !_showOutline, () => setState(() => _showOutline = false)),
                      _tabButton('📋 大纲', _showOutline, () => setState(() => _showOutline = true)),
                    ],
                  ),
                ),
                if (!_showOutline && hasSvg) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.zoom_in_rounded, size: 18, color: Color(0xFF475569)),
                    tooltip: '放大',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: _zoomIn,
                  ),
                  IconButton(
                    icon: const Icon(Icons.zoom_out_rounded, size: 18, color: Color(0xFF475569)),
                    tooltip: '缩小',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: _zoomOut,
                  ),
                  IconButton(
                    icon: const Icon(Icons.restart_alt_rounded, size: 18, color: Color(0xFF475569)),
                    tooltip: '重置比例',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: _resetZoom,
                  ),
                  IconButton(
                    icon: const Icon(Icons.download_rounded, size: 18, color: Color(0xFF475569)),
                    tooltip: '导出矢量 SVG',
                    splashRadius: 14,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                    onPressed: _exportSvg,
                  ),
                ],
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF94A3B8)),
                  tooltip: '删除导图',
                  splashRadius: 14,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                  onPressed: _deleteBlock,
                ),
              ],
            ),
          ),
          // 主体展示：高清无损矢量导图 或 结构化大纲
          if (!_showOutline && hasSvg)
            Container(
              height: 480,
              color: Colors.white,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
                child: InteractiveViewer(
                  transformationController: _transformCtrl,
                  minScale: 0.1,
                  maxScale: 6.0,
                  boundaryMargin: const EdgeInsets.all(400),
                  child: Center(
                    child: SvgPicture.file(
                      File(_svgPath!),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            )
          else
            Container(
              height: 420,
              padding: const EdgeInsets.all(16),
              color: Colors.white,
              child: _tree != null
                  ? SingleChildScrollView(child: _buildTreeNode(_tree!, 0))
                  : Center(
                      child: Text(
                        hasSvg ? '切换到大纲模式' : '导图矢量附件尚未同步，暂无大纲结构数据',
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          boxShadow: active ? const [BoxShadow(color: Colors.black12, blurRadius: 2)] : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
            color: active ? const Color(0xFF1E293B) : const Color(0xFF64748B),
          ),
        ),
      ),
    );
  }

  Widget _buildTreeNode(Map<String, dynamic> node, int level) {
    final rawName = node['name']?.toString() ?? '';
    final rawHtml = node['html']?.toString() ?? '';
    final name = rawName.isNotEmpty ? rawName : rawHtml.replaceAll(RegExp(r'<[^>]+>'), '');
    final children = (node['children'] as List<dynamic>?)?.cast<Map<String, dynamic>>() ?? [];

    return Padding(
      padding: EdgeInsets.only(left: level * 20.0, top: 4, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                level == 0 ? Icons.folder_open_rounded : Icons.subdirectory_arrow_right_rounded,
                size: 16,
                color: level == 0 ? const Color(0xFF2563EB) : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: level == 0 ? const Color(0xFFEFF6FF) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: level == 0 ? const Color(0xFFBFDBFE) : const Color(0xFFE2E8F0),
                  ),
                ),
                child: Text(
                  name.isEmpty ? '节点' : name,
                  style: TextStyle(
                    fontSize: level == 0 ? 14 : 12,
                    fontWeight: level == 0 ? FontWeight.bold : FontWeight.w500,
                    color: level == 0 ? const Color(0xFF1E3A8A) : const Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
          for (final ch in children) _buildTreeNode(ch, level + 1),
        ],
      ),
    );
  }
}
