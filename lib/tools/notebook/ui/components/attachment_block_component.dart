import 'dart:io';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../convert/matrix.dart';
import '../../convert/ui/convert_dialog.dart';
import '../../note_store.dart';

class AttachmentBlockKeys {
  AttachmentBlockKeys._();
  static const String type = 'attachment';
  static const String attachmentId = 'attachmentId';
  static const String filename = 'filename';
  static const String sizeBytes = 'sizeBytes';
  static const String mime = 'mime';

  /// 早期版本曾把文件路径直接缓存进节点。现仅作为 legacy 回退读取，
  /// 新写入的节点不再包含此字段——附件路径的唯一真相是 attachments 表。
  static const String localPath = 'localPath';
}

/// 构造附件块节点。
///
/// 刻意不写入文件路径：路径由 [AttachmentBlockKeys.attachmentId] 在渲染时
/// 从 attachments 表解析，避免"引用用户原始文件路径"导致源文件被删后附件失效。
Node attachmentNode({
  required String attachmentId,
  required String filename,
  required int sizeBytes,
  String? mime,
}) {
  return Node(
    type: AttachmentBlockKeys.type,
    attributes: {
      AttachmentBlockKeys.attachmentId: attachmentId,
      AttachmentBlockKeys.filename: filename,
      AttachmentBlockKeys.sizeBytes: sizeBytes,
      if (mime != null) AttachmentBlockKeys.mime: mime,
    },
  );
}

class AttachmentBlockComponentBuilder extends BlockComponentBuilder {
  AttachmentBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return AttachmentBlockComponentWidget(
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
  BlockComponentValidate get validate => (node) =>
      node.type == AttachmentBlockKeys.type;
}

class AttachmentBlockComponentWidget extends BlockComponentStatefulWidget {
  const AttachmentBlockComponentWidget({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<AttachmentBlockComponentWidget> createState() =>
      _AttachmentBlockComponentWidgetState();
}

class _AttachmentBlockComponentWidgetState
    extends State<AttachmentBlockComponentWidget>
    with BlockComponentConfigurable {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  String get _filename =>
      node.attributes[AttachmentBlockKeys.filename] as String? ?? '附件';
  int get _sizeBytes =>
      node.attributes[AttachmentBlockKeys.sizeBytes] as int? ?? 0;
  String? get _attachmentId =>
      node.attributes[AttachmentBlockKeys.attachmentId] as String?;
  String? get _mime => node.attributes[AttachmentBlockKeys.mime] as String?;

  /// 是否为图片附件：优先看节点上的 mime（导入时写入），
  /// 老节点没有 mime 时退回按扩展名判断——两者都不命中才按非图片渲染。
  bool get _isImage {
    final m = _mime;
    if (m != null && m.isNotEmpty) return m.startsWith('image/');
    final ext = _filename.toLowerCase().split('.').last;
    return const {'png', 'jpg', 'jpeg', 'gif', 'bmp', 'webp'}.contains(ext);
  }

  /// 早期版本写入节点内的缓存路径（legacy 回退用）。
  String? get _legacyCachedPath =>
      node.attributes[AttachmentBlockKeys.localPath] as String?;

  /// 已解析出的附件路径（来自 attachments 表；legacy 节点回退到缓存路径）。
  String? _resolvedPath;
  bool _resolving = true;

  @override
  void initState() {
    super.initState();
    _resolvePath();
  }

  /// 附件路径的真相来源是 attachments 表——按 attachmentId 查表，
  /// 而非信任节点内缓存的路径（否则用户删除源文件后引用即失效）。
  /// 查表失败时回退到早期版本缓存的路径，保证旧笔记仍可渲染。
  Future<void> _resolvePath() async {
    final attId = _attachmentId;
    String? resolved;
    if (attId != null && attId.isNotEmpty) {
      try {
        final att = await NoteStore.instance.attachmentById(attId);
        resolved = att?.localPath;
      } catch (e, st) {
        // 查表失败（DB 不可用等）→ 走 legacy 回退；打印以便调试
        debugPrint('[附件解析] 查表异常 attId=$attId  error=$e\n$st');
      }
    }
    resolved ??= _legacyCachedPath;
    if (!mounted) return;
    setState(() {
      _resolvedPath = resolved;
      _resolving = false;
    });
  }

  /// 附件是否可用：路径存在且文件真实存在。
  bool get _available {
    final p = _resolvedPath;
    return p != null && p.isNotEmpty && File(p).existsSync();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        crossAxisAlignment: _isImage ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          if (_isImage)
            _buildThumbnail()
          else
            Icon(_iconFor(_filename), size: 22, color: const Color(0xFF64748B)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _filename,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF334155),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _resolving
                      ? '解析中…'
                      : (_available ? _formatSize(_sizeBytes) : '附件不可用'),
                  style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                ),
              ],
            ),
          ),
          if (!_resolving && _available) ...[
            if (_canConvert)
              TextButton.icon(
                onPressed: () => _convert(context),
                icon: const Icon(Icons.transform_rounded, size: 14),
                label: const Text('转换', style: TextStyle(fontSize: 11)),
              ),
            TextButton.icon(
              onPressed: _revealInFinder,
              icon: const Icon(Icons.folder_open, size: 14),
              label: const Text('在访达中显示', style: TextStyle(fontSize: 11)),
            ),
            TextButton.icon(
              onPressed: () => _saveAs(context),
              icon: const Icon(Icons.download_rounded, size: 14),
              label: const Text('另存为', style: TextStyle(fontSize: 11)),
            ),
            TextButton.icon(
              onPressed: () => _confirmDelete(context),
              icon: const Icon(Icons.delete_outline_rounded, size: 14, color: Colors.redAccent),
              label: const Text('删除', style: TextStyle(fontSize: 11, color: Colors.redAccent)),
            ),
          ],
        ],
      ),
    );
  }

  /// 图片缩略图：约束宽度、等比缩放，点击用系统默认应用打开原图。
  ///
  /// 为什么是缩略而非原图直显：附件块嵌在长笔记流里，一张几 MB 的原图
  /// 会把版面冲散。缩略兼顾可扫读性，需要原图时点一下即可。
  Widget _buildThumbnail() {
    final p = _resolvedPath;
    if (p == null || !File(p).existsSync()) {
      return const SizedBox(width: 96, height: 72);
    }
    return GestureDetector(
      onTap: () => Process.run('open', [p]),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 120, maxHeight: 120),
          child: Image.file(
            File(p),
            width: 120,
            fit: BoxFit.cover,
            // 解码失败（文件损坏/格式不支持）时退回图标，不显示破图。
            errorBuilder: (_, __, ___) => Container(
              width: 96,
              height: 72,
              alignment: Alignment.center,
              child: Icon(_iconFor(_filename), size: 28, color: const Color(0xFF94A3B8)),
            ),
          ),
        ),
      ),
    );
  }

  bool get _canConvert {
    final ext = _filename.toLowerCase().split('.').last;
    return DocFormat.fromExtension(ext) != null;
  }

  void _convert(BuildContext context) {
    final attId = _attachmentId;
    final p = _resolvedPath;
    if (attId == null || p == null) return;

    EditorState? editorState;
    try {
      editorState = context.read<EditorState>();
    } catch (_) {}

    ConvertDialog.show(
      context,
      attachmentId: attId,
      filename: _filename,
      localPath: p,
      onConvertedAttachment: (newAtt) {
        if (editorState != null) {
          try {
            final f = File(newAtt.localPath);
            final size = f.existsSync() ? f.lengthSync() : 0;
            final newNode = attachmentNode(
              attachmentId: newAtt.id,
              filename: newAtt.filename ?? 'attachment',
              sizeBytes: size,
              mime: newAtt.mime,
            );
            final transaction = editorState.transaction;
            transaction.insertNode(widget.node.path.next, newNode);
            editorState.apply(transaction);
          } catch (e) {
            debugPrint('自动插入转换产物节点失败: $e');
          }
        }
      },
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('删除确认'),
          ],
        ),
        content: Text('确定要从笔记中删除附件「$_filename」吗？\n删除后该附件内容将从正文和附件库中彻底移除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // 1. 从编辑器文档树中删除当前节点
    try {
      final editorState = context.read<EditorState>();
      final transaction = editorState.transaction;
      transaction.deleteNode(widget.node);
      await editorState.apply(transaction);
    } catch (e) {
      debugPrint('删除编辑器节点失败: $e');
    }

    // 2. 级联清理 SQLite 数据库和磁盘物理文件
    final attId = _attachmentId;
    if (attId != null && attId.isNotEmpty) {
      try {
        await NoteStore.instance.deleteAttachment(attId);
      } catch (e) {
        debugPrint('清理附件存储失败: $e');
      }
    }
  }

  Future<void> _revealInFinder() async {
    final p = _resolvedPath;
    if (p == null) return;
    await Process.run('open', ['-R', p]);
  }

  Future<void> _saveAs(BuildContext context) async {
    final p = _resolvedPath;
    if (p == null) return;
    final outputDir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: '选择保存位置',
    );
    if (outputDir == null) return;
    final dest = File('$outputDir/$_filename');
    await File(p).copy(dest.path);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已保存到 ${dest.path}')),
      );
    }
  }

  static IconData _iconFor(String filename) {
    final ext = filename.toLowerCase().split('.').last;
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'png':
      case 'jpg':
      case 'jpeg':
      case 'gif':
        return Icons.image_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
