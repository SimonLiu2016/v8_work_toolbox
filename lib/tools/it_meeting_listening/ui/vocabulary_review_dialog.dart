import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../services/vocabulary_session_controller.dart';
import '../services/vocabulary_study_store.dart';

/// 复习定制配置结果。
class VocabularyReviewConfig {
  final ReviewTimeRange timeRange;
  final VocabularyPracticeMode mode;
  final bool isShuffled;
  final List<String> words;

  const VocabularyReviewConfig({
    required this.timeRange,
    required this.mode,
    required this.isShuffled,
    required this.words,
  });
}

/// 轻量级复习定制弹窗：选择时间范围、考核模式及是否随机打乱出题。
class VocabularyReviewDialog extends StatefulWidget {
  final VocabularyStudyStore studyStore;
  final ReviewTimeRange initialRange;
  final VocabularyPracticeMode initialMode;
  final bool initialShuffled;

  const VocabularyReviewDialog({
    super.key,
    required this.studyStore,
    this.initialRange = ReviewTimeRange.today,
    this.initialMode = VocabularyPracticeMode.quiz4Choice,
    this.initialShuffled = true,
  });

  static Future<VocabularyReviewConfig?> show(
    BuildContext context, {
    required VocabularyStudyStore studyStore,
    ReviewTimeRange initialRange = ReviewTimeRange.today,
    VocabularyPracticeMode initialMode = VocabularyPracticeMode.quiz4Choice,
    bool initialShuffled = true,
  }) {
    return showDialog<VocabularyReviewConfig>(
      context: context,
      builder: (_) => VocabularyReviewDialog(
        studyStore: studyStore,
        initialRange: initialRange,
        initialMode: initialMode,
        initialShuffled: initialShuffled,
      ),
    );
  }

  @override
  State<VocabularyReviewDialog> createState() => _VocabularyReviewDialogState();
}

class _VocabularyReviewDialogState extends State<VocabularyReviewDialog> {
  late ReviewTimeRange _selectedRange;
  late VocabularyPracticeMode _selectedMode;
  late bool _isShuffled;

  @override
  void initState() {
    super.initState();
    _selectedRange = widget.initialRange;
    _selectedMode = widget.initialMode;
    _isShuffled = widget.initialShuffled;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final bgCard = isDark ? context.bgCard : AppTheme.lightBgCard;
    final border = isDark ? context.borderSubtle : AppTheme.lightBorderSubtle;
    final textPrimary =
        isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? context.textSecondary : AppTheme.lightTextSecondary;
    final accent = context.accentText;

    final targetWords = widget.studyStore.getWordsStudiedInRange(_selectedRange);
    final count = targetWords.length;

    return Dialog(
      backgroundColor: bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 460,
          maxWidth: 520,
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 头部：标题与关闭
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withValues(alpha: 0.12),
                    ),
                    child: Icon(Icons.bolt_rounded, size: 20, color: accent),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '复习定制',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '自选时间范围与模式，检验记忆效果',
                          style: TextStyle(
                            fontSize: 12,
                            color: textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: '关闭',
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 1. 时间范围选择
              Text(
                '复习时间范围',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: ReviewTimeRange.values.map((range) {
                  final rangeCount =
                      widget.studyStore.countWordsStudiedInRange(range);
                  final isSelected = _selectedRange == range;
                  return ChoiceChip(
                    key: ValueKey('review-range-chip-${range.name}'),
                    label: Text('${range.label} ($rangeCount)'),
                    selected: isSelected,
                    onSelected: (_) => setState(() => _selectedRange = range),
                    selectedColor: accent.withValues(alpha: 0.18),
                    backgroundColor:
                        isDark ? context.bgInput : Colors.grey.shade100,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? accent : textSecondary,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: BorderSide(
                        color: isSelected ? accent : border,
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // 2. 考核模式选择
              Text(
                '考核方式',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildModeOptionCard(
                      key: const ValueKey('review-mode-quiz'),
                      title: '盲听测验',
                      subtitle: '4 选 1 听辨释义',
                      icon: Icons.quiz_rounded,
                      isSelected:
                          _selectedMode == VocabularyPracticeMode.quiz4Choice,
                      onTap: () => setState(() => _selectedMode =
                          VocabularyPracticeMode.quiz4Choice),
                      accent: accent,
                      border: border,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildModeOptionCard(
                      key: const ValueKey('review-mode-flashcards'),
                      title: '闪卡自评',
                      subtitle: '翻牌回忆并自评',
                      icon: Icons.style_rounded,
                      isSelected:
                          _selectedMode == VocabularyPracticeMode.flashcards,
                      onTap: () => setState(() => _selectedMode =
                          VocabularyPracticeMode.flashcards),
                      accent: accent,
                      border: border,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      isDark: isDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // 3. 随机出题开关
              InkWell(
                key: const ValueKey('review-shuffle-toggle'),
                borderRadius: BorderRadius.circular(8),
                onTap: () => setState(() => _isShuffled = !_isShuffled),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: Checkbox(
                          value: _isShuffled,
                          activeColor: accent,
                          onChanged: (val) =>
                              setState(() => _isShuffled = val ?? true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '随机打乱出题顺序',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: textPrimary,
                              ),
                            ),
                            Text(
                              '打破线性前后位置记忆，测试更贴近实战',
                              style: TextStyle(
                                fontSize: 11,
                                color: textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // 底部动作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: border),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    child: Text('取消', style: TextStyle(color: textSecondary)),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    key: const ValueKey('review-start-submit-btn'),
                    onPressed: count == 0
                        ? null
                        : () {
                            final finalWords = _isShuffled
                                ? (List<String>.from(targetWords)..shuffle())
                                : List<String>.from(targetWords);

                            Navigator.of(context).pop(
                              VocabularyReviewConfig(
                                timeRange: _selectedRange,
                                mode: _selectedMode,
                                isShuffled: _isShuffled,
                                words: finalWords,
                              ),
                            );
                          },
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(count == 0 ? '暂无复习词汇' : '开始复习 (共 $count 词)'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeOptionCard({
    required Key key,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required Color accent,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required bool isDark,
  }) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? accent : border,
            width: isSelected ? 1.5 : 1.0,
          ),
          color: isSelected
              ? accent.withValues(alpha: 0.08)
              : (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.white),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected ? accent : textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: isSelected ? accent : textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
