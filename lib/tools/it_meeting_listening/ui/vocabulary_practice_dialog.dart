import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../services/vocabulary_session_controller.dart';
import '../services/vocabulary_study_store.dart';

/// 沉浸式词汇练习与考核对话框（学习 / 盲听测验 / 闪卡自评 / 错题强化）。
class VocabularyPracticeDialog extends StatefulWidget {
  final VocabularySessionController session;
  final Future<void> Function(String text)? onPlayTts;

  const VocabularyPracticeDialog({
    super.key,
    required this.session,
    this.onPlayTts,
  });

  static Future<void> show(
    BuildContext context, {
    required VocabularySessionController session,
    Future<void> Function(String text)? onPlayTts,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => VocabularyPracticeDialog(
        session: session,
        onPlayTts: onPlayTts,
      ),
    );
  }

  @override
  State<VocabularyPracticeDialog> createState() =>
      _VocabularyPracticeDialogState();
}

class _VocabularyPracticeDialogState extends State<VocabularyPracticeDialog> {
  late VocabularySessionController _session;
  final FocusNode _focusNode = FocusNode();
  String? _playingText;
  bool _resumedFromProgress = false;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    _resumedFromProgress = _session.currentIndex > 0;
    _session.addListener(_onSessionChanged);

    _saveCurrentProgress();

    // 页面载入时自动播放首题发音
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _autoPlayCurrentWord();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _saveCurrentProgress() {
    if (_session.isCompleted) {
      _session.studyStore.clearPracticeProgress(_session.mode.name);
    } else {
      final item = _session.currentItem;
      if (item != null) {
        _session.studyStore.savePracticeProgress(_session.mode.name, item.word);
        if (_session.mode == VocabularyPracticeMode.study) {
          _session.studyStore.recordWordStudied(item.word);
        }
      }
    }
  }

  void _onSessionChanged() {
    _saveCurrentProgress();
    if (mounted) setState(() {});
  }

  void _resetToBeginning() {
    _session.resetToBeginning();
    _resumedFromProgress = false;
    _saveCurrentProgress();
    _autoPlayCurrentWord();
  }

  void _autoPlayCurrentWord() {
    final item = _session.currentItem;
    if (item != null) {
      _playText(item.word);
    }
  }

  Future<void> _playText(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final item = _session.currentItem;
    if (item != null && item.word == trimmed && !item.isAnswered) {
      _session.recordPlay();
    }
    setState(() => _playingText = trimmed);
    try {
      if (widget.onPlayTts != null) {
        await widget.onPlayTts!(trimmed);
      }
    } finally {
      if (mounted && _playingText == trimmed) {
        setState(() => _playingText = null);
      }
    }
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    final item = _session.currentItem;
    if (item == null || _session.isCompleted) return;

    if (event.logicalKey == LogicalKeyboardKey.space) {
      // 空格键：重播发音或翻牌
      if (_session.mode == VocabularyPracticeMode.flashcards &&
          !item.isCardFlipped) {
        _session.flipCard();
      } else {
        _playText(item.word);
      }
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.arrowRight) {
      // 回车或向右键：进入下一题（若已作答或学习模式）
      if (_session.mode == VocabularyPracticeMode.study || item.isAnswered) {
        _handleNext();
      }
      return;
    }

    if (event.logicalKey == LogicalKeyboardKey.arrowLeft &&
        _session.mode == VocabularyPracticeMode.study) {
      // 向左键：回退上一个（仅学习模式）
      _handlePrevious();
      return;
    }

    // 数字键 1-4
    if (_session.mode == VocabularyPracticeMode.quiz4Choice) {
      if (!item.isAnswered) {
        if (event.logicalKey == LogicalKeyboardKey.digit1 &&
            item.choices.isNotEmpty) {
          _session.selectChoice(0);
        } else if (event.logicalKey == LogicalKeyboardKey.digit2 &&
            item.choices.length > 1) {
          _session.selectChoice(1);
        } else if (event.logicalKey == LogicalKeyboardKey.digit3 &&
            item.choices.length > 2) {
          _session.selectChoice(2);
        } else if (event.logicalKey == LogicalKeyboardKey.digit4 &&
            item.choices.length > 3) {
          _session.selectChoice(3);
        }
      }
    } else if (_session.mode == VocabularyPracticeMode.flashcards &&
        item.isCardFlipped) {
      if (event.logicalKey == LogicalKeyboardKey.digit1) {
        _handleSelfAssessment(0);
      } else if (event.logicalKey == LogicalKeyboardKey.digit2) {
        _handleSelfAssessment(1);
      } else if (event.logicalKey == LogicalKeyboardKey.digit3) {
        _handleSelfAssessment(2);
      } else if (event.logicalKey == LogicalKeyboardKey.digit4) {
        _handleSelfAssessment(3);
      }
    }
  }

  void _handleNext() {
    final advanced = _session.next();
    if (advanced) {
      _autoPlayCurrentWord();
    }
  }

  void _handlePrevious() {
    final back = _session.previous();
    if (back) {
      _autoPlayCurrentWord();
    }
  }

  void _handleSelfAssessment(int rating) {
    _session.submitSelfAssessment(rating);
    if (!_session.isCompleted) {
      _autoPlayCurrentWord();
    }
  }

  void _restartMistakes() {
    final newSession = _session.createMistakesSession();
    if (newSession != null) {
      _session.removeListener(_onSessionChanged);
      setState(() {
        _session = newSession;
        _session.addListener(_onSessionChanged);
      });
      _autoPlayCurrentWord();
    }
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

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _handleKeyEvent,
      child: Dialog(
        backgroundColor: bgCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: 640,
            maxWidth: 720,
            minHeight: 460,
            maxHeight: 600,
          ),
          child: _session.isCompleted
              ? _buildSummaryView(context, isDark, accent, border, textPrimary, textSecondary)
              : _buildActivePracticeView(context, isDark, accent, border, textPrimary, textSecondary),
        ),
      ),
    );
  }

  Widget _buildActivePracticeView(
    BuildContext context,
    bool isDark,
    Color accent,
    Color border,
    Color textPrimary,
    Color textSecondary,
  ) {
    final item = _session.currentItem;
    final total = _session.totalCount;
    final curr = _session.currentIndex + 1;
    final progress = total > 0 ? (curr / total).clamp(0.0, 1.0) : 0.0;

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部导航栏：退出按钮 · 模式标签 · 进度指示
          Row(
            children: [
              IconButton(
                key: const ValueKey('vocab-practice-close-btn'),
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close_rounded, size: 20),
                tooltip: '退出练习 (Esc)',
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: accent.withValues(alpha: 0.12),
                ),
                child: Text(
                  _session.mode.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              InkWell(
                key: const ValueKey('vocab-practice-accent-toggle-btn'),
                onTap: () {
                  final nextAccent =
                      _session.studyStore.accent == VocabularyAccent.us
                          ? VocabularyAccent.uk
                          : VocabularyAccent.us;
                  _session.studyStore.setAccent(nextAccent);
                  setState(() {});
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border),
                    color:
                        isDark ? const Color(0xFF1E2129) : Colors.grey.shade100,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.volume_up_outlined, size: 12, color: accent),
                      const SizedBox(width: 4),
                      Text(
                        _session.studyStore.accent.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_resumedFromProgress) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.amber.withValues(alpha: 0.15),
                    border: Border.all(
                      color: Colors.amber.shade700.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.history_rounded,
                        size: 13,
                        color: isDark ? Colors.amber.shade300 : Colors.amber.shade900,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '已接续上次进度',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_session.pendingReinforceCount > 0) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    color: Colors.orange.withValues(alpha: 0.15),
                    border: Border.all(
                      color: Colors.orange.shade700.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.queue_rounded,
                        size: 13,
                        color: isDark ? Colors.orange.shade300 : Colors.orange.shade900,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '末尾待强化: ${_session.pendingReinforceCount}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isDark ? Colors.orange.shade200 : Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(width: 6),
              TextButton.icon(
                key: const ValueKey('vocab-practice-reset-btn'),
                onPressed: _resetToBeginning,
                icon: const Icon(Icons.restart_alt_rounded, size: 14),
                label: const Text('从头开始', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              const Spacer(),
              Text(
                '$curr / $total',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: isDark ? context.bgInput : Colors.grey.shade200,
            color: accent,
            minHeight: 4,
            borderRadius: BorderRadius.circular(2),
          ),
          const SizedBox(height: 16),
          // 核心练习卡片区
          Expanded(
            child: item == null
                ? const SizedBox.shrink()
                : SingleChildScrollView(
                    child: switch (_session.mode) {
                      VocabularyPracticeMode.study => _buildStudyCard(
                          item, isDark, accent, border, textPrimary, textSecondary),
                      VocabularyPracticeMode.quiz4Choice => _buildQuizCard(
                          item, isDark, accent, border, textPrimary, textSecondary),
                      VocabularyPracticeMode.flashcards => _buildFlashcard(
                          item, isDark, accent, border, textPrimary, textSecondary),
                    },
                  ),
          ),
          const SizedBox(height: 16),
          // 底部控制按钮栏
          _buildBottomActionRow(item, accent, textPrimary, textSecondary),
        ],
      ),
    );
  }

  Widget _buildAudioPlayButton({
    required Key key,
    required VoidCallback onTap,
    required bool isPlaying,
    required Color accent,
    required String tooltip,
    double iconSize = 22,
    double buttonSize = 42,
    IconData? idleIcon,
  }) {
    final effectiveIdleIcon = idleIcon ?? Icons.volume_up_rounded;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: isPlaying ? accent : accent.withValues(alpha: 0.12),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: key,
          onTap: onTap,
          hoverColor: accent.withValues(alpha: 0.22),
          child: SizedBox(
            width: buttonSize,
            height: buttonSize,
            child: Center(
              child: Icon(
                isPlaying ? Icons.graphic_eq_rounded : effectiveIdleIcon,
                size: iconSize,
                color: isPlaying ? Colors.white : accent,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. 沉浸刷词学习卡片 (Study)
  // ---------------------------------------------------------------------------
  Widget _buildStudyCard(
    PracticeItem item,
    bool isDark,
    Color accent,
    Color border,
    Color textPrimary,
    Color textSecondary,
  ) {
    final profile = item.profile;
    final isWordPlaying = _playingText == item.word;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 10),
        // 单词拼写与发音按钮
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              item.word,
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: textPrimary,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(width: 12),
            _buildAudioPlayButton(
              key: ValueKey('practice-word-play-btn-${item.word}'),
              onTap: () => _playText(item.word),
              isPlaying: isWordPlaying,
              accent: accent,
              tooltip: '播放发音 (空格键)',
              iconSize: 22,
              buttonSize: 42,
            ),
          ],
        ),
        const SizedBox(height: 6),
        // 音标与词性
        if (profile != null && profile.phonetic.isNotEmpty)
          Text(
            '${profile.phonetic} · ${profile.partOfSpeech}',
            style: TextStyle(
              fontSize: 14,
              color: textSecondary,
              fontFamily: 'monospace',
            ),
          ),
        const SizedBox(height: 12),
        // 中文释义
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: accent.withValues(alpha: 0.08),
          ),
          child: Text(
            profile?.definitionZh.isNotEmpty == true
                ? profile!.definitionZh
                : '暂无中文释义',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
        ),
        const SizedBox(height: 24),
        // 真实会议原句语境
        if (item.contextSentence != null)
          _buildContextSentenceSection(item, isDark, accent, border, textPrimary, textSecondary),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // 2. 盲听 4 选 1 测验卡片 (Quiz 4-choice)
  // ---------------------------------------------------------------------------
  Widget _buildQuizCard(
    PracticeItem item,
    bool isDark,
    Color accent,
    Color border,
    Color textPrimary,
    Color textSecondary,
  ) {
    final isAnswered = item.isAnswered;
    final isWordPlaying = _playingText == item.word;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (item.isReinforcement) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: Colors.deepOrange.withValues(alpha: 0.12),
              border: Border.all(
                color: Colors.deepOrange.shade600.withValues(alpha: 0.35),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.replay_rounded,
                  size: 13,
                  color: isDark ? Colors.orangeAccent : Colors.deepOrange,
                ),
                const SizedBox(width: 4),
                Text(
                  '生疏强化加测 · 加深听音辨析印记',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.orangeAccent : Colors.deepOrange,
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        // 盲听提示与发音大按钮
        _buildAudioPlayButton(
          key: ValueKey('quiz-blind-play-btn-${item.word}'),
          onTap: () => _playText(item.word),
          isPlaying: isWordPlaying,
          accent: accent,
          tooltip: '重新播放发音 (空格键)',
          iconSize: 38,
          buttonSize: 76,
        ),
        const SizedBox(height: 12),
        Text(
          isAnswered ? item.word : '听音辨析 · 请选出正确释义',
          style: TextStyle(
            fontSize: isAnswered ? 26 : 14,
            fontWeight: isAnswered ? FontWeight.bold : FontWeight.w500,
            color: isAnswered ? textPrimary : textSecondary,
          ),
        ),
        if (isAnswered && item.profile != null && item.profile!.phonetic.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              item.profile!.phonetic,
              style: TextStyle(fontSize: 13, color: textSecondary, fontFamily: 'monospace'),
            ),
          ),
        if (isAnswered && item.familiarity != null) ...[
          const SizedBox(height: 10),
          _buildFamiliarityDiagnosisBanner(item, isDark),
        ],
        const SizedBox(height: 16),
        // 4 个中文释义选项
        for (var i = 0; i < item.choices.length; i++) ...[
          _buildQuizOptionTile(item, i, isDark, accent, border, textPrimary, textSecondary),
          const SizedBox(height: 8),
        ],
        // 作答后展开会议原句出处
        if (isAnswered && item.contextSentence != null) ...[
          const SizedBox(height: 16),
          _buildContextSentenceSection(item, isDark, accent, border, textPrimary, textSecondary),
        ],
      ],
    );
  }

  /// 盲听熟悉度评估与排期诊断微章条。
  Widget _buildFamiliarityDiagnosisBanner(PracticeItem item, bool isDark) {
    final familiarity = item.familiarity;
    if (familiarity == null) return const SizedBox.shrink();

    Color color;
    IconData icon;
    String title;
    String subtitle;

    switch (familiarity) {
      case AuditoryFamiliarity.instant:
        color = Colors.teal;
        icon = Icons.bolt_rounded;
        title = '⚡ 听音 1 次 · 秒懂精通';
        subtitle = '听音反应敏捷迅速，已延长下次复习排期';
        break;
      case AuditoryFamiliarity.normal:
        color = Colors.green;
        icon = Icons.check_circle_outline_rounded;
        title = '✓ 听音 1 次 · 基本掌握';
        subtitle = '听辨准确清晰，按科学间隔正常排期';
        break;
      case AuditoryFamiliarity.hesitant:
        color = Colors.amber.shade800;
        icon = Icons.psychology_alt_rounded;
        title = '🤔 听音 2 次 · 迟疑辨析';
        subtitle = '盲听稍显犹豫，熟练度保持，明天再次安排复习巩固';
        break;
      case AuditoryFamiliarity.struggling:
        color = Colors.deepOrange;
        icon = Icons.warning_amber_rounded;
        title = '⚠️ 听音 ${item.playCount} 次 · 辨音吃力';
        subtitle = item.isReinforcement
            ? '重听多次才辨析出，已缩短复习间隔至今日'
            : '重听多次才辨析出，已缩短复习间隔至今日并在末尾加测';
        break;
      case AuditoryFamiliarity.lapse:
        color = Colors.red.shade600;
        icon = Icons.highlight_off_rounded;
        title = '❌ 辨音盲区 · 选错释义';
        subtitle = item.isReinforcement
            ? '熟练度已重置，已安排今日强化复习'
            : '熟练度已重置，已安排今日强化并在末尾追加重测';
        break;
    }

    return Container(
      key: const ValueKey('vocab-familiarity-diagnosis-banner'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: isDark ? 0.16 : 0.08),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.4 : 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuizOptionTile(
    PracticeItem item,
    int index,
    bool isDark,
    Color accent,
    Color border,
    Color textPrimary,
    Color textSecondary,
  ) {
    final isAnswered = item.isAnswered;
    final isSelected = item.selectedChoiceIndex == index;
    final isCorrectOption = index == item.correctChoiceIndex;

    Color tileBg = isDark ? context.bgInput : Colors.grey.shade50;
    Color tileBorder = border;
    Color optLabelColor = textSecondary;
    IconData? statusIcon;

    if (isAnswered) {
      if (isCorrectOption) {
        tileBg = Colors.green.withValues(alpha: 0.15);
        tileBorder = Colors.green.shade600;
        optLabelColor = Colors.green.shade700;
        statusIcon = Icons.check_circle_rounded;
      } else if (isSelected) {
        tileBg = Colors.red.withValues(alpha: 0.15);
        tileBorder = Colors.red.shade400;
        optLabelColor = Colors.red.shade700;
        statusIcon = Icons.cancel_rounded;
      }
    }

    return InkWell(
      key: ValueKey('quiz-choice-$index'),
      borderRadius: BorderRadius.circular(10),
      onTap: isAnswered ? null : () => _session.selectChoice(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tileBorder),
          color: tileBg,
        ),
        child: Row(
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: optLabelColor.withValues(alpha: 0.12),
              ),
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: optLabelColor,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                item.choices[index],
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isAnswered && (isSelected || isCorrectOption)
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: textPrimary,
                ),
              ),
            ),
            if (statusIcon != null)
              Icon(statusIcon, size: 20, color: optLabelColor),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Anki 闪卡翻牌自评 (Flashcards)
  // ---------------------------------------------------------------------------
  Widget _buildFlashcard(
    PracticeItem item,
    bool isDark,
    Color accent,
    Color border,
    Color textPrimary,
    Color textSecondary,
  ) {
    final isFlipped = item.isCardFlipped;
    final isWordPlaying = _playingText == item.word;

    return Column(
      children: [
        const SizedBox(height: 12),
        InkWell(
          key: const ValueKey('flashcard-flip-target'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => _session.flipCard(),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1.5),
              color: isDark ? context.bgInput : Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // 发音按钮
                _buildAudioPlayButton(
                  key: ValueKey('flashcard-play-btn-${item.word}'),
                  onTap: () => _playText(item.word),
                  isPlaying: isWordPlaying,
                  accent: accent,
                  tooltip: '播放发音 (空格键)',
                  iconSize: 32,
                  buttonSize: 64,
                ),
                const SizedBox(height: 12),
                if (!isFlipped) ...[
                  Text(
                    '？在脑海中回忆它的意思与会议语境',
                    style: TextStyle(fontSize: 14, color: textSecondary),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '（点击卡片或按空格键翻牌）',
                    style: TextStyle(fontSize: 12, color: accent),
                  ),
                ] else ...[
                  Text(
                    item.word,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                  if (item.profile != null && item.profile!.phonetic.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${item.profile!.phonetic} · ${item.profile!.partOfSpeech}',
                      style: TextStyle(fontSize: 13, color: textSecondary, fontFamily: 'monospace'),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Text(
                    item.profile?.definitionZh.isNotEmpty == true
                        ? item.profile!.definitionZh
                        : '暂无中文释义',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: accent,
                    ),
                  ),
                  if (item.contextSentence != null) ...[
                    const SizedBox(height: 16),
                    _buildContextSentenceSection(item, isDark, accent, border, textPrimary, textSecondary),
                  ],
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        // 翻牌后的自评按键 (1: 遗忘, 2: 模糊, 3: 熟悉, 4: 秒懂)
        if (isFlipped)
          Row(
            children: [
              Expanded(
                child: _buildAssessmentButton(
                  key: 'assess-btn-0',
                  label: '1. 遗忘',
                  desc: '重置',
                  color: Colors.red.shade700,
                  onTap: () => _handleSelfAssessment(0),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAssessmentButton(
                  key: 'assess-btn-1',
                  label: '2. 模糊',
                  desc: '1天后',
                  color: Colors.orange.shade800,
                  onTap: () => _handleSelfAssessment(1),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAssessmentButton(
                  key: 'assess-btn-2',
                  label: '3. 熟悉',
                  desc: '进阶',
                  color: Colors.blue.shade700,
                  onTap: () => _handleSelfAssessment(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildAssessmentButton(
                  key: 'assess-btn-3',
                  label: '4. 秒懂',
                  desc: '牢记',
                  color: Colors.green.shade700,
                  onTap: () => _handleSelfAssessment(3),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildAssessmentButton({
    required String key,
    required String label,
    required String desc,
    required Color color,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      key: ValueKey(key),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 10),
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        backgroundColor: color.withValues(alpha: 0.08),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
          Text(desc, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.8))),
        ],
      ),
    );
  }

  // 真实会议原句语境通用卡片
  Widget _buildContextSentenceSection(
    PracticeItem item,
    bool isDark,
    Color accent,
    Color border,
    Color textPrimary,
    Color textSecondary,
  ) {
    final sentence = item.contextSentence ?? '';
    final isSentencePlaying = _playingText == sentence;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: isDark ? context.bgWindow : Colors.grey.shade50,
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.forum_outlined, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                '${item.speaker ?? '说话人'} · ${item.sceneLabel ?? '研发会议'}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: accent,
                ),
              ),
              const Spacer(),
              InkWell(
                key: ValueKey('practice-sentence-play-btn-${item.word}'),
                onTap: () => _playText(sentence),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isSentencePlaying ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                        size: 13,
                        color: accent,
                      ),
                      const SizedBox(width: 3),
                      Text('听原句', style: TextStyle(fontSize: 11, color: accent)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            sentence,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: textPrimary,
              height: 1.4,
            ),
          ),
          if (item.sentenceTranslation != null) ...[
            const SizedBox(height: 4),
            Text(
              item.sentenceTranslation!,
              style: TextStyle(
                fontSize: 12,
                color: textSecondary,
                height: 1.3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 底部控制行
  Widget _buildBottomActionRow(
    PracticeItem? item,
    Color accent,
    Color textPrimary,
    Color textSecondary,
  ) {
    if (_session.mode == VocabularyPracticeMode.study) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          OutlinedButton.icon(
            key: const ValueKey('vocab-practice-prev-btn'),
            onPressed: _session.isFirst ? null : _handlePrevious,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('上一个 (←)'),
          ),
          FilledButton.icon(
            key: const ValueKey('vocab-practice-next-btn'),
            onPressed: _handleNext,
            icon: Icon(_session.isLast ? Icons.check_circle_rounded : Icons.arrow_forward_rounded, size: 16),
            label: Text(_session.isLast ? '完成学习' : '下一个 (Enter/→)'),
          ),
        ],
      );
    }

    if (_session.mode == VocabularyPracticeMode.quiz4Choice) {
      final isAnswered = item?.isAnswered == true;
      return Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          FilledButton.icon(
            key: const ValueKey('vocab-quiz-next-btn'),
            onPressed: isAnswered ? _handleNext : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: Text(_session.isLast ? '查看成绩' : '下一题 (Enter)'),
          ),
        ],
      );
    }

    // 闪卡模式：翻牌前显示“翻牌”，翻牌后由 4 个自评按钮直接触发切题
    if (!item!.isCardFlipped) {
      return Center(
        child: FilledButton.icon(
          key: const ValueKey('vocab-flashcard-flip-btn'),
          onPressed: () => _session.flipCard(),
          icon: const Icon(Icons.flip_rounded, size: 16),
          label: const Text('翻牌查看解析 (空格)'),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ---------------------------------------------------------------------------
  // 4. 答题报告结算卡 (Summary)
  // ---------------------------------------------------------------------------
  Widget _buildSummaryView(
    BuildContext context,
    bool isDark,
    Color accent,
    Color border,
    Color textPrimary,
    Color textSecondary,
  ) {
    final mistakes = _session.mistakeWords;
    final total = _session.totalCount;
    final correct = _session.correctCount;
    final accuracy = total > 0 ? ((correct / total) * 100).round() : 100;

    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.emoji_events_rounded, size: 56, color: Colors.amber),
          const SizedBox(height: 12),
          Text(
            '会话完成！',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _session.mode == VocabularyPracticeMode.quiz4Choice
                ? '总题数: $total · 正确数: $correct · 正确率: $accuracy%'
                : '本次共学习/复习了 $total 个重点词汇，记忆状态已自动排期',
            style: TextStyle(fontSize: 13, color: textSecondary),
          ),
          const SizedBox(height: 20),
          // 易错词总结
          if (mistakes.isNotEmpty) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '待巩固词汇 (${mistakes.length} 词)：',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade700,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: border),
                  color: isDark ? context.bgWindow : Colors.grey.shade50,
                ),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  itemCount: mistakes.length,
                  separatorBuilder: (_, __) => Divider(color: border, height: 1),
                  itemBuilder: (context, idx) {
                    final w = mistakes[idx];
                    final p = _session.studyStore.profileFor(w);
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Text(
                            w,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: textPrimary,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              p?.definitionZh ?? '',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12, color: textSecondary),
                            ),
                          ),
                          IconButton(
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _playText(w),
                            icon: const Icon(Icons.volume_down_rounded),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ] else ...[
            const Spacer(),
            Icon(Icons.check_circle_outline_rounded, size: 48, color: Colors.green.shade600),
            const SizedBox(height: 8),
            Text(
              '太棒了！本次没有错误词汇，已全部掌握！',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.green.shade700),
            ),
            const Spacer(),
          ],
          const SizedBox(height: 20),
          // 底部操作按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (mistakes.isNotEmpty) ...[
                FilledButton.tonalIcon(
                  key: const ValueKey('vocab-practice-retry-mistakes-btn'),
                  onPressed: _restartMistakes,
                  icon: const Icon(Icons.replay_rounded, size: 16),
                  label: Text('重练错题 (${mistakes.length})'),
                ),
                const SizedBox(width: 14),
              ],
              FilledButton(
                key: const ValueKey('vocab-practice-finish-btn'),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('完成并返回'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
