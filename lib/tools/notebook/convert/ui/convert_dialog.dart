import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../note_database.dart';
import '../../note_store.dart';
import '../conversion_engine.dart';
import '../matrix.dart';
import '../translator.dart';

/// 附件文档一键转换与翻译对话框。
class ConvertDialog extends StatefulWidget {
  const ConvertDialog({
    super.key,
    required this.attachmentId,
    required this.filename,
    required this.localPath,
    this.onConverted,
    this.onConvertedAttachment,
  });

  final String attachmentId;
  final String filename;
  final String localPath;
  final VoidCallback? onConverted;
  final ValueChanged<Attachment>? onConvertedAttachment;

  static Future<void> show(
    BuildContext context, {
    required String attachmentId,
    required String filename,
    required String localPath,
    VoidCallback? onConverted,
    ValueChanged<Attachment>? onConvertedAttachment,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ConvertDialog(
        attachmentId: attachmentId,
        filename: filename,
        localPath: localPath,
        onConverted: onConverted,
        onConvertedAttachment: onConvertedAttachment,
      ),
    );
  }

  @override
  State<ConvertDialog> createState() => _ConvertDialogState();
}

class _ConvertDialogState extends State<ConvertDialog> {
  late DocFormat _sourceFormat;
  late List<DocFormat> _targets;
  late DocFormat _selectedTarget;

  bool _translate = true;
  String _sourceLang = '英语';
  String _targetLang = '中文';

  bool _isConverting = false;
  String _statusMessage = '';
  double _progress = 0.0;

  bool _isSuccess = false;
  String _savedPath = '';
  String _savedFilename = '';
  int _savedSize = 0;

  static const List<String> _languages = [
    '中文',
    '英语',
    '日语',
    '韩语',
    '法语',
    '德语',
    '西班牙语',
    '俄语',
  ];

  @override
  void initState() {
    super.initState();
    final ext = p.extension(widget.filename).replaceFirst('.', '').toLowerCase();
    _sourceFormat = DocFormat.fromExtension(ext) ?? DocFormat.txt;
    _targets = availableTargets(_sourceFormat);
    _selectedTarget = _targets.isNotEmpty ? _targets.first : _sourceFormat;
  }

  Future<void> _startConversion() async {
    setState(() {
      _isConverting = true;
      _statusMessage = '正在读取附件文件...';
      _progress = 0.0;
    });

    try {
      final sourceFile = File(widget.localPath);
      if (!sourceFile.existsSync()) {
        throw Exception('源附件文件在磁盘上不存在');
      }

      final bytes = await sourceFile.readAsBytes();

      setState(() {
        _statusMessage = _translate ? '正在翻译与转换格式...' : '正在转换文件格式...';
      });

      final convertedBytes = await ConversionEngine.convert(
        bytes: bytes,
        sourceFormat: _sourceFormat,
        targetFormat: _selectedTarget,
        translate: _translate,
        sourceLang: _sourceLang,
        targetLang: _targetLang,
        onProgress: (completed, total) {
          if (!mounted) return;
          setState(() {
            _progress = total > 0 ? completed / total : 0.0;
            _statusMessage = '正在处理文本批次 ($completed / $total)...';
          });
        },
      );

      setState(() {
        _statusMessage = '正在保存转换产物到附件库...';
      });

      // 查询当前附件记录以获取 noteId
      final att = await NoteStore.instance.attachmentById(widget.attachmentId);
      if (att == null) {
        throw Exception('附件元数据不存在');
      }

      // 生成产物文件名：原文件名_目标语言_to_目标格式.扩展名
      final baseName = p.basenameWithoutExtension(widget.filename);
      final langSuffix = _translate ? '_$_targetLang' : '';
      final newFilename = '$baseName${langSuffix}_to_${_selectedTarget.extension}.${_selectedTarget.extension}';

      // 写入临时文件然后调用 addAttachment
      final tempDir = Directory.systemTemp.createTempSync('v8_convert_');
      final tempFile = File(p.join(tempDir.path, newFilename));
      await tempFile.writeAsBytes(convertedBytes);

      final newAttId = await NoteStore.instance.addAttachment(
        noteId: att.noteId,
        sourceFile: tempFile,
      );

      final newAtt = await NoteStore.instance.attachmentById(newAttId);

      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}

      if (!mounted) return;

      widget.onConverted?.call();
      if (newAtt != null) {
        widget.onConvertedAttachment?.call(newAtt);
      }

      setState(() {
        _isConverting = false;
        _isSuccess = true;
        _savedFilename = newFilename;
        _savedPath = newAtt?.localPath ?? '';
        _savedSize = convertedBytes.length;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConverting = false;
        _statusMessage = '';
      });

      showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red),
              SizedBox(width: 8),
              Text('转换失败'),
            ],
          ),
          content: Text(
            e is PdfNoTextLayerException
                ? e.message
                : e is DocumentTranslationException
                    ? '文档翻译失败：\n${e.message}\n\n请检查 AI 服务配置或网络连接，未生成未翻译产物。'
                    : '处理出错：$e',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('确定'),
            ),
          ],
        ),
      );
    }
  }

  void _revealInFinder() {
    if (_savedPath.isNotEmpty) {
      Process.run('open', ['-R', _savedPath]);
    }
  }

  void _openFile() {
    if (_savedPath.isNotEmpty) {
      Process.run('open', [_savedPath]);
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    if (_isSuccess) {
      return _buildSuccessDialog();
    }

    final tier = conversionTier(_sourceFormat, _selectedTarget);
    final tierDesc = switch (tier) {
      ConversionTier.t1 => '排版与图片零变化（原地文本替换）',
      ConversionTier.t2 => '内容与图片完整保留（排版尽力还原）',
      ConversionTier.unavailable => '不支持该转换',
    };

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.transform_rounded, size: 22, color: Colors.blueAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '一键转换与翻译：${widget.filename}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text('源文件格式：', style: TextStyle(fontWeight: FontWeight.w600)),
                Text(_sourceFormat.label),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('目标格式：', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButton<DocFormat>(
                    value: _selectedTarget,
                    isExpanded: true,
                    items: _targets.map((fmt) {
                      return DropdownMenuItem(
                        value: fmt,
                        child: Text(fmt.label),
                      );
                    }).toList(),
                    onChanged: _isConverting
                        ? null
                        : (fmt) {
                            if (fmt != null) {
                              setState(() => _selectedTarget = fmt);
                            }
                          },
                  ),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 12),
              child: Text(
                '还原度级别：$tierDesc',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            const Divider(),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('启用内容语言翻译'),
              subtitle: const Text('关闭则仅转换文件格式，保持原文不变', style: TextStyle(fontSize: 12)),
              value: _translate,
              onChanged: _isConverting
                  ? null
                  : (val) {
                      setState(() => _translate = val ?? true);
                    },
            ),
            if (_translate) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('源语言', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        DropdownButton<String>(
                          value: _sourceLang,
                          isExpanded: true,
                          items: _languages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                          onChanged: _isConverting ? null : (v) => setState(() => _sourceLang = v!),
                        ),
                      ],
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Icon(Icons.arrow_forward, size: 16, color: Colors.grey),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('目标语言', style: TextStyle(fontSize: 12, color: Colors.black54)),
                        DropdownButton<String>(
                          value: _targetLang,
                          isExpanded: true,
                          items: _languages.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                          onChanged: _isConverting ? null : (v) => setState(() => _targetLang = v!),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            if (_isConverting) ...[
              const SizedBox(height: 16),
              LinearProgressIndicator(value: _progress > 0 ? _progress : null),
              const SizedBox(height: 8),
              Center(
                child: Text(
                  _statusMessage,
                  style: const TextStyle(fontSize: 12, color: Colors.blueAccent),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (!_isConverting)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ElevatedButton.icon(
          onPressed: _isConverting ? null : _startConversion,
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: const Text('开始转换'),
        ),
      ],
    );
  }

  Widget _buildSuccessDialog() {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 24, color: Colors.green),
          SizedBox(width: 8),
          Text('转换完成！', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.insert_drive_file_outlined, size: 20, color: Color(0xFF334155)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _savedFilename,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        _formatSize(_savedSize),
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('保存在：', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                  SelectableText(
                    _savedPath,
                    style: const TextStyle(fontSize: 11, color: Color(0xFF334155)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '✓ 新生成的文件已自动添加到当前笔记正文中。',
              style: TextStyle(fontSize: 12, color: Colors.green),
            ),
          ],
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: _revealInFinder,
          icon: const Icon(Icons.folder_open, size: 16),
          label: const Text('在访达中显示'),
        ),
        OutlinedButton.icon(
          onPressed: _openFile,
          icon: const Icon(Icons.open_in_new, size: 16),
          label: const Text('打开文件'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('完成'),
        ),
      ],
    );
  }
}
