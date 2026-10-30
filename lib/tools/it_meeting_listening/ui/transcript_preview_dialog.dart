/// 导入前的解析预览。
///
/// **为什么要有这一步**：格式放宽之后，"解析成功"不再等价于"这是我要的那场
/// 会"。一份看着像逐字稿的文档被按错的方式理解，代价不是一次报错，而是一条
/// 二十分钟的假音频加几百次语音合成调用。这张卡片把判断权交回用户，成本是
/// 一次点击。
library;

import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../services/real_meeting_service.dart';

/// 解析预览对话框。
///
/// 返回 `true` 表示用户确认导入。
class TranscriptPreviewDialog extends StatelessWidget {
  final TranscriptPreview preview;

  const TranscriptPreviewDialog({super.key, required this.preview});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final bg = isDark ? context.bgCard : AppTheme.lightBgCard;
    final textPrimary = isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? context.textSecondary : AppTheme.lightTextSecondary;
    final accent = context.accentText;

    return Dialog(
      backgroundColor: bg,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 620),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.fact_check_outlined, size: 18, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(preview.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: textPrimary)),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(preview.fileName,
                  style: TextStyle(fontSize: 11, color: textSecondary)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  _stat('${preview.turnCount} 轮', accent, textSecondary),
                  _stat('${preview.slotIds.length} 个说话人', accent, textSecondary),
                  _stat(_fmtDuration(preview.durationMs), accent, textSecondary),
                ],
              ),
              const SizedBox(height: 10),
              if (preview.contentUnchanged)
                _note('这份文稿内容未变，确认后将直接使用已有的音频，不会重新合成。',
                    accent, textPrimary),
              if (preview.isProcessedDocument)
                _note('这是一份人工整理的归档件（含说明/附录）。系统只解析其中的原文轮次，'
                    '说明表格与附录会被跳过。', accent, textPrimary),
              if (preview.keywordsMissing)
                _note('没有找到「关键词」段：词汇表仍能统计，但低频词更容易被折叠成'
                    '「疑似转写噪声」。', accent, textPrimary),
              const SizedBox(height: 8),
              Text('说话人：${preview.slotIds.join(' · ')}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: textSecondary)),
              const Divider(height: 16),
              Text('前几轮长这样',
                  style: TextStyle(fontSize: 11, color: textSecondary)),
              const SizedBox(height: 4),
              Expanded(
                child: ListView.builder(
                  itemCount: preview.samples.length,
                  itemBuilder: (context, i) {
                    final s = preview.samples[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 96,
                            child: Text(s.slot,
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: accent)),
                          ),
                          Expanded(
                            child: Text(s.text,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 12, color: textPrimary)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(context, true),
                    icon: const Icon(Icons.graphic_eq_rounded, size: 16),
                    label: Text(preview.contentUnchanged ? '使用已有音频' : '确认并合成'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stat(String text, Color accent, Color textSecondary) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(text, style: TextStyle(fontSize: 11, color: accent)),
      );

  Widget _note(String text, Color accent, Color textPrimary) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(text, style: TextStyle(fontSize: 11, color: textPrimary)),
        ),
      );

  static String _fmtDuration(int ms) {
    if (ms <= 0) return '时长未知';
    final total = ms ~/ 1000;
    final h = total ~/ 3600;
    final m = (total % 3600) ~/ 60;
    final s = total % 60;
    if (h > 0) return '$h 小时 $m 分';
    if (m > 0) return '$m 分 $s 秒';
    return '$s 秒';
  }
}
