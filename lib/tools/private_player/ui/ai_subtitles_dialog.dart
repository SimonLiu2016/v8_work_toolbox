import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../../services/ai_config_store.dart';
import '../../../theme/app_theme.dart';
import '../services/ai_subtitle_service.dart';
import '../services/media_history_store.dart';
import '../services/private_player_controller.dart';
import '../services/private_storage_manager.dart';

/// AI 语音转字幕操作与导出弹窗
class AiSubtitlesDialog extends StatefulWidget {
  final PrivatePlayerController controller;

  const AiSubtitlesDialog({
    super.key,
    required this.controller,
  });

  static Future<void> show(BuildContext context, PrivatePlayerController controller) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AiSubtitlesDialog(controller: controller),
    );
  }

  @override
  State<AiSubtitlesDialog> createState() => _AiSubtitlesDialogState();
}

class _AiSubtitlesDialogState extends State<AiSubtitlesDialog> {
  final AiSubtitleService _subtitleService = AiSubtitleService.instance;

  bool _isGenerating = false;
  String _statusText = '';
  double _progressPct = 0.0;
  String _errorText = '';

  int _selectedMode = 0; // 0: 按需区间 (前后10分钟), 1: 全量完整生成
  bool _autoTranslateZh = true; // 是否同步调用文本大模型翻译为中文字幕

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final hasSubtitles = ctrl.subtitles.isNotEmpty;
    final sttCandidates = AiConfigStore.instance.slotBindings['stt'] ?? [];

    return Dialog(
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.borderSubtle),
      ),
      child: Container(
        width: 520,
        padding: const EdgeInsets.all(AppTheme.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题与关闭
            Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome_rounded, color: AppTheme.accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'AI 语音识别转字幕',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                      ),
                      Text(
                        '当前视频: ${ctrl.currentTitle}',
                        style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20, color: AppTheme.textSecondary),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),

            const SizedBox(height: AppTheme.space20),

            // AI STT 槽位状态提示
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.bgCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.borderSubtle),
              ),
              child: Row(
                children: [
                  Icon(
                    sttCandidates.isNotEmpty ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
                    size: 16,
                    color: sttCandidates.isNotEmpty ? AppTheme.success : Colors.amber,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sttCandidates.isNotEmpty
                          ? '已绑定 STT 槽位: ${sttCandidates.first.model} (${sttCandidates.first.providerId})'
                          : '未显式绑定 STT 槽位，将尝试匹配可用 OpenAI 语音接口',
                      style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.space16),

            // 生成模式单选
            const Text(
              '选择字幕生成模式：',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 8),

            RadioGroup<int>(
              groupValue: _selectedMode,
              onChanged: (v) {
                if (_isGenerating || v == null) return;
                setState(() => _selectedMode = v);
              },
              child: Column(
                children: [
                  RadioListTile<int>(
                    value: 0,
                    activeColor: AppTheme.accent,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('极速全量生成完整字幕 (推荐)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                    subtitle: Text(
                      '优先直取原生/内嵌轨，无内置时最速提取整片轻量音频并发调用 AI 转录，整片时间轴无缝同步',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ),
                  RadioListTile<int>(
                    value: 1,
                    activeColor: AppTheme.accent,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('按当前播放点生成切片 (快速调试)', style: TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
                    subtitle: Text(
                      '仅提取当前播放位置 (${_formatDuration(ctrl.position)}) 前后约 10 分钟音频快速生成局部字幕',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // 是否调用大模型翻译为中文字幕
            CheckboxListTile(
              value: _autoTranslateZh,
              onChanged: _isGenerating
                  ? null
                  : (val) => setState(() => _autoTranslateZh = val ?? true),
              title: const Text(
                '生成后调用 AI 文本模型翻译为中文字幕 (推荐)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
              ),
              subtitle: const Text(
                '调用全局配置的 text 槽位大模型，将字幕分批全量翻译为中英双语字幕',
                style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
              ),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              activeColor: AppTheme.accent,
            ),

            // 进度与状态反馈
            if (_isGenerating) ...[
              const SizedBox(height: AppTheme.space16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progressPct > 0 ? _progressPct : null,
                  backgroundColor: AppTheme.bgCard,
                  valueColor: const AlwaysStoppedAnimation(AppTheme.accent),
                  minHeight: 6,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _statusText,
                style: const TextStyle(fontSize: 12, color: AppTheme.accent),
              ),
            ],

            if (_errorText.isNotEmpty) ...[
              const SizedBox(height: AppTheme.space12),
              Text(
                _errorText,
                style: const TextStyle(color: AppTheme.error, fontSize: 12),
              ),
            ],

            const SizedBox(height: AppTheme.space20),

            // 底部操作按钮
            Row(
              children: [
                if (hasSubtitles) ...[
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppTheme.textPrimary,
                      side: const BorderSide(color: AppTheme.borderSubtle),
                    ),
                    icon: const Icon(Icons.file_download_outlined, size: 16),
                    label: const Text('导出 .SRT 字幕文件'),
                    onPressed: _exportSrtFile,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '已加载 ${ctrl.subtitles.length} 条字幕',
                    style: const TextStyle(color: AppTheme.success, fontSize: 12),
                  ),
                ],
                const Spacer(),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  ),
                  icon: _isGenerating
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: Text(_isGenerating ? '处理中...' : '开始生成字幕'),
                  onPressed: _isGenerating ? null : _startGeneration,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _startGeneration() async {
    final ctrl = widget.controller;
    final src = ctrl.currentSource;
    if (src == null) return;

    setState(() {
      _isGenerating = true;
      _errorText = '';
      _statusText = '准备音频中...';
      _progressPct = 0.0;
    });

    try {
      List<SubtitleSegment> segments;

      if (_selectedMode == 0) {
        segments = await _subtitleService.fastGenerateSubtitles(
          videoPathOrUrl: src,
          title: ctrl.currentTitle,
          duration: ctrl.duration,
          onProgress: (st, pct) {
            if (mounted) {
              setState(() {
                _statusText = st;
                if (pct != null) _progressPct = pct * (_autoTranslateZh ? 0.6 : 1.0);
              });
            }
          },
        );
      } else {
        segments = await _subtitleService.generateIntervalSubtitles(
          videoPathOrUrl: src,
          currentPosition: ctrl.position,
          onStatus: (st) {
            if (mounted) setState(() => _statusText = st);
          },
        );
      }

      if (_autoTranslateZh && segments.isNotEmpty) {
        if (mounted) {
          setState(() {
            _statusText = '正在调用 AI 文本大模型翻译为中文字幕...';
            _progressPct = 0.65;
          });
        }
        segments = await _subtitleService.translateSubtitleSegments(
          originalSegments: segments,
          bilingual: true,
          onProgress: (st, pct) {
            if (mounted) {
              setState(() {
                _statusText = st;
                if (pct != null) _progressPct = 0.65 + pct * 0.34;
              });
            }
          },
        );
      }

      ctrl.setSubtitles(segments);
      ctrl.toggleSubtitles(true); // 自动开启字幕

      // 自动异步保存至私密目录
      final safeTitle = ctrl.currentTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
      final fileName = _autoTranslateZh ? '${safeTitle}_zh.srt' : '$safeTitle.srt';
      final targetFile = File(p.join(PrivateStorageManager.instance.subtitlesDir.path, fileName));
      await _subtitleService.saveSubtitleFile(
        title: safeTitle,
        segments: segments,
        customPath: targetFile.path,
      );

      // 同步更新播放历史中关联的字幕路径
      await MediaHistoryStore.instance.updateSubtitlePath(
        urlOrPath: src,
        subtitlePath: targetFile.path,
      );

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _statusText = _autoTranslateZh ? '中文字幕已生成完毕并加载至播放器' : '字幕已生成完毕并加载至播放器';
          _progressPct = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _errorText = e.toString().replaceAll('Exception: ', '');
        });
      }
    }
  }

  Future<void> _exportSrtFile() async {
    final ctrl = widget.controller;
    if (ctrl.subtitles.isEmpty) return;

    final defaultName = '${ctrl.currentTitle.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')}.srt';
    final savePath = await FilePicker.platform.saveFile(
      dialogTitle: '导出字幕文件',
      fileName: defaultName,
      type: FileType.custom,
      allowedExtensions: ['srt'],
    );

    if (savePath != null) {
      await _subtitleService.saveSubtitleFile(
        title: ctrl.currentTitle,
        segments: ctrl.subtitles,
        customPath: savePath,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('字幕已成功导出至: $savePath'),
            backgroundColor: AppTheme.bgCard,
          ),
        );
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
