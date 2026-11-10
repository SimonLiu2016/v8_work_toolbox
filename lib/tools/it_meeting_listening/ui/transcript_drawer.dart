/// 全局精听右侧抽屉与逐句文稿视图（Group 9.2）。
///
/// 布局：
/// - 宽屏（>= 960px）下作为右侧推挤栏（宽 420px）展开；
/// - 窄屏（< 960px）下作为右侧浮层覆盖展开；
/// - 始终跟随当前正在播放的 `Clip`；
/// - 默认收起，开始播放新条目不会自动展开；
/// - 支持标准视图、意群断句视图（带连读弱读标注）与盲听遮罩视图；
/// - 提供单句死循环（🔁）跟读与长难句复盘本（⭐）快速摘录。
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../theme/app_theme.dart';
import '../models/listening_models.dart';
import '../models/real_meeting_models.dart';
import '../models/sentence_vault_models.dart';
import '../services/connected_speech_marker.dart';
import '../services/listening_player_controller.dart';
import '../services/sense_group_chunker.dart';
import '../services/sentence_vault_store.dart';
import '../services/term_highlighter.dart';
import 'sentence_vault_dialog.dart';

/// 精听文稿排版视图模式
enum TranscriptViewMode {
  /// 标准视图（完整段落 + 术语高亮）
  standard,

  /// 意群分块视图（按认知意群拆行 + 停顿符 // + 辅元连读/弱读标识）
  senseGroup,

  /// 盲听遮罩视图（先用耳朵抓取主干，点击翻开原文）
  blindMask,
}

class TranscriptDrawer extends StatefulWidget {
  final Clip? clip;
  final int currentTurnIndex;
  final VoidCallback onClose;
  final ValueChanged<int> onSeekToTurn;
  final void Function(Clip clip, SpeakerTurn turn, String term) onCollectTerm;
  final ValueChanged<int> onOpenAnswerComposer;
  final ValueChanged<SpeakerTurn> onOpenAnswerActions;
  final ListeningPlayerController? player;
  final VoidCallback? onOpenSentenceVault;

  const TranscriptDrawer({
    super.key,
    required this.clip,
    required this.currentTurnIndex,
    required this.onClose,
    required this.onSeekToTurn,
    required this.onCollectTerm,
    required this.onOpenAnswerComposer,
    required this.onOpenAnswerActions,
    this.player,
    this.onOpenSentenceVault,
  });

  static bool _isRehearsal(Clip clip) => clip.source.sourceId == 'rehearsal';
  static bool _isRealMeeting(Clip clip) =>
      clip.source.sourceId == 'real-meeting';

  @override
  State<TranscriptDrawer> createState() => _TranscriptDrawerState();
}

class _TranscriptDrawerState extends State<TranscriptDrawer> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  final Set<int> _revealedTurns = {};
  bool _userInteracted = false;
  TranscriptViewMode _viewMode = TranscriptViewMode.standard;

  @override
  void initState() {
    super.initState();
    SentenceVaultStore.instance.init();
    SentenceVaultStore.instance.addListener(_onVaultChanged);
    widget.player?.addListener(_onPlayerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.currentTurnIndex >= 0) {
        _scrollToTurn(widget.currentTurnIndex, animated: false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant TranscriptDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.player != widget.player) {
      oldWidget.player?.removeListener(_onPlayerChanged);
      widget.player?.addListener(_onPlayerChanged);
    }
    final clipChanged = oldWidget.clip?.id != widget.clip?.id;
    if (clipChanged) {
      _userInteracted = false;
      _itemKeys.clear();
      _revealedTurns.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && widget.currentTurnIndex >= 0) {
          _scrollToTurn(widget.currentTurnIndex, animated: false);
        }
      });
    } else if (oldWidget.currentTurnIndex != widget.currentTurnIndex) {
      if (!_userInteracted && widget.currentTurnIndex >= 0) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_userInteracted) {
            _scrollToTurn(widget.currentTurnIndex, animated: true);
          }
        });
      }
    }
  }

  @override
  void dispose() {
    SentenceVaultStore.instance.removeListener(_onVaultChanged);
    widget.player?.removeListener(_onPlayerChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onVaultChanged() {
    if (mounted) setState(() {});
  }

  void _onPlayerChanged() {
    if (mounted) setState(() {});
  }

  void _scrollToTurn(int index, {required bool animated}) {
    if (!mounted || !_scrollController.hasClients) return;
    final turns = widget.clip?.turns;
    if (turns == null || index < 0 || index >= turns.length) return;

    final key = _itemKeys[index];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: animated ? const Duration(milliseconds: 300) : Duration.zero,
        curve: Curves.easeInOut,
      );
    } else {
      if (_scrollController.hasClients &&
          _scrollController.position.hasContentDimensions) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final target = (index / turns.length) * maxScroll;
        _scrollController.jumpTo(target);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final retryCtx = _itemKeys[index]?.currentContext;
          if (retryCtx != null) {
            Scrollable.ensureVisible(
              retryCtx,
              alignment: 0.5,
              duration: animated
                  ? const Duration(milliseconds: 200)
                  : Duration.zero,
              curve: Curves.easeInOut,
            );
          }
        });
      }
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

    final activeClip = widget.clip;

    return Container(
      key: const ValueKey('transcript-drawer'),
      width: 440,
      decoration: BoxDecoration(
        color: bgCard,
        border: Border(left: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 抽屉顶栏（标题 + 关闭按钮）
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.menu_book_rounded, size: 16, color: accent),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            activeClip != null
                                ? '精听 · ${activeClip.title}'
                                : '精听文稿',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: textPrimary,
                            ),
                          ),
                          if (activeClip != null &&
                              activeClip.summary.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                activeClip.summary,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 11, color: textSecondary),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // 打开长难句复盘本
                    _buildSentenceVaultHeaderButton(context, accent, textSecondary),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const ValueKey('transcript-drawer-close'),
                      tooltip: '关闭精听',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.onClose,
                      icon: Icon(Icons.close_rounded,
                          size: 18, color: textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // 视图模式切换栏：标准 / 意群 / 盲听
                Row(
                  children: [
                    _buildModeButton(
                      label: '标准原文',
                      icon: Icons.article_outlined,
                      mode: TranscriptViewMode.standard,
                      accent: accent,
                      textSecondary: textSecondary,
                      border: border,
                    ),
                    const SizedBox(width: 6),
                    _buildModeButton(
                      label: '意群断句',
                      icon: Icons.format_line_spacing_rounded,
                      mode: TranscriptViewMode.senseGroup,
                      accent: accent,
                      textSecondary: textSecondary,
                      border: border,
                    ),
                    const SizedBox(width: 6),
                    _buildModeButton(
                      label: '盲听遮罩',
                      icon: Icons.visibility_off_outlined,
                      mode: TranscriptViewMode.blindMask,
                      accent: accent,
                      textSecondary: textSecondary,
                      border: border,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // 逐句列表
          Expanded(
            child: activeClip == null
                ? Center(
                    child: Text(
                      '尚未选择播放条目',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                  )
                : Stack(
                    children: [
                      NotificationListener<UserScrollNotification>(
                        onNotification: (notification) {
                          if (notification.direction != ScrollDirection.idle) {
                            if (!_userInteracted) {
                              setState(() {
                                _userInteracted = true;
                              });
                            }
                          }
                          return false;
                        },
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                          itemCount: activeClip.turns.length,
                          itemBuilder: (context, i) {
                            final turn = activeClip.turns[i];
                            final active = i == widget.currentTurnIndex;
                            final isMeeting =
                                TranscriptDrawer._isRehearsal(activeClip) ||
                                    TranscriptDrawer._isRealMeeting(activeClip);
                            final isAnswer =
                                turn.role == InsertedAnswer.roleMarker;
                            final itemKey =
                                _itemKeys.putIfAbsent(i, () => GlobalKey());
                            final isLoopingThis =
                                widget.player?.loopingTurnIndex == i;
                            final isVaultSaved = SentenceVaultStore.instance
                                .isSaved(activeClip.id, i);

                            return Container(
                              key: itemKey,
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: isLoopingThis
                                    ? Colors.amber.withValues(alpha: 0.15)
                                    : (active
                                        ? accent.withValues(alpha: 0.10)
                                        : Colors.transparent),
                                borderRadius: BorderRadius.circular(6),
                                border: isLoopingThis
                                    ? Border.all(
                                        color: Colors.amber.shade600,
                                        width: 1.2,
                                      )
                                    : null,
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // 左侧说话人栏（点击跳转到该句播放）
                                  InkWell(
                                    borderRadius: BorderRadius.circular(4),
                                    onTap: isMeeting
                                        ? () => widget.onSeekToTurn(turn.startMs)
                                        : null,
                                    child: Tooltip(
                                      message: isMeeting ? '点击跳到此处播放' : '',
                                      child: SizedBox(
                                        width: 88,
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              isMeeting
                                                  ? '${turn.speaker}${isAnswer ? ' · 我的回答' : ''}:'
                                                  : turn.displayName,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: active
                                                    ? accent
                                                    : textSecondary,
                                                fontWeight: isMeeting
                                                    ? FontWeight.w600
                                                    : FontWeight.normal,
                                              ),
                                            ),
                                            if (isLoopingThis)
                                              Container(
                                                margin: const EdgeInsets.only(
                                                    top: 2),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 4,
                                                  vertical: 1,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: Colors.amber
                                                      .withValues(alpha: 0.25),
                                                  borderRadius:
                                                      BorderRadius.circular(3),
                                                ),
                                                child: Text(
                                                  '循环中',
                                                  style: TextStyle(
                                                    fontSize: 9,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.amber.shade900,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  // 核心发言正文排版（按模式呈现，支持鼠标自由拖选与复制）
                                  Expanded(
                                    child: _buildTurnContent(
                                      i,
                                      turn,
                                      active,
                                      textPrimary,
                                      textSecondary,
                                      accent,
                                      isDark,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  // 一键快捷复制按钮 (📋)
                                  Tooltip(
                                    message: _viewMode == TranscriptViewMode.senseGroup
                                        ? '复制意群断句文本（// 停顿排版，可供 AI 评估）'
                                        : '复制纯英文文本（便于向 AI 发问）',
                                    child: IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(
                                        minWidth: 24,
                                        minHeight: 24,
                                      ),
                                      icon: Icon(
                                        Icons.copy_rounded,
                                        size: 14,
                                        color: textSecondary.withValues(alpha: 0.7),
                                      ),
                                      onPressed: () => _copyTurnText(turn),
                                    ),
                                  ),
                                  // 单句死循环跟读按钮
                                  if (isMeeting)
                                    Tooltip(
                                      message: isLoopingThis
                                          ? '退出单句循环'
                                          : '单句循环跟读（按块复述）',
                                      child: IconButton(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 24,
                                          minHeight: 24,
                                        ),
                                        icon: Icon(
                                          Icons.repeat_one_rounded,
                                          size: 15,
                                          color: isLoopingThis
                                              ? Colors.amber.shade800
                                              : textSecondary
                                                  .withValues(alpha: 0.7),
                                        ),
                                        onPressed: () {
                                          widget.player?.toggleLoopingTurn(i);
                                        },
                                      ),
                                    ),
                                  // 难句复盘本摘录按钮 (⭐)
                                    Tooltip(
                                      message: isVaultSaved
                                          ? '已收藏至长难句本（点击管理/移出）'
                                          : '摘录为长难句（放入复盘本）',
                                      child: IconButton(
                                        visualDensity: VisualDensity.compact,
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 24,
                                          minHeight: 24,
                                        ),
                                        icon: Icon(
                                          isVaultSaved
                                              ? Icons.star_rounded
                                              : Icons.star_outline_rounded,
                                          size: 16,
                                          color: isVaultSaved
                                              ? Colors.amber
                                              : textSecondary
                                                  .withValues(alpha: 0.7),
                                        ),
                                        onPressed: () => _openSaveVaultDialog(
                                          activeClip,
                                          i,
                                          turn,
                                        ),
                                      ),
                                    ),
                                    if (TranscriptDrawer._isRealMeeting(
                                            activeClip) &&
                                        isAnswer)
                                      IconButton(
                                        tooltip: '修改或删除这条回答',
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 15,
                                        color: textSecondary,
                                        icon: const Icon(Icons.more_horiz),
                                        onPressed: () =>
                                            widget.onOpenAnswerActions(turn),
                                      ),
                                    if (TranscriptDrawer._isRealMeeting(
                                            activeClip) &&
                                        !isAnswer)
                                      IconButton(
                                        tooltip: '就这一轮提问，插入我的回答',
                                        visualDensity: VisualDensity.compact,
                                        iconSize: 15,
                                        color: textSecondary,
                                        icon: const Icon(
                                            Icons.question_answer_outlined),
                                        onPressed: () =>
                                            widget.onOpenAnswerComposer(i),
                                      ),
                                    _buildCollectTermButton(
                                      activeClip,
                                      turn,
                                      textSecondary,
                                    ),
                                  ],
                                ),
                              );
                          },
                        ),
                      ),
                      if (_userInteracted && widget.currentTurnIndex >= 0)
                        Positioned(
                          right: 16,
                          bottom: 16,
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: const ValueKey(
                                  'transcript-return-to-current-btn'),
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                setState(() {
                                  _userInteracted = false;
                                });
                                _scrollToTurn(
                                  widget.currentTurnIndex,
                                  animated: true,
                                );
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.95),
                                  borderRadius: BorderRadius.circular(16),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          Colors.black.withValues(alpha: 0.2),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.arrow_downward_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                    SizedBox(width: 4),
                                    Text(
                                      '回到正在朗读句',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentenceVaultHeaderButton(
    BuildContext context,
    Color accent,
    Color textSecondary,
  ) {
    final count = SentenceVaultStore.instance.totalCount;
    return Tooltip(
      message: '打开长难句复盘本 ($count)',
      child: InkWell(
        borderRadius: BorderRadius.circular(4),
        onTap: () {
          if (widget.onOpenSentenceVault != null) {
            widget.onOpenSentenceVault!();
          } else {
            showDialog<void>(
              context: context,
              builder: (_) => SentenceVaultDialog(player: widget.player),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Colors.amber.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
              const SizedBox(width: 2),
              Text(
                '难句本 ($count)',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeButton({
    required String label,
    required IconData icon,
    required TranscriptViewMode mode,
    required Color accent,
    required Color textSecondary,
    required Color border,
  }) {
    final isSelected = _viewMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: () {
        setState(() {
          _viewMode = mode;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? accent : border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 13,
              color: isSelected ? accent : textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? accent : textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _copyTurnText(SpeakerTurn turn) {
    String textToCopy;
    if (_viewMode == TranscriptViewMode.senseGroup) {
      final chunks = SenseGroupChunker.chunk(turn.rawText);
      final buffer = StringBuffer();
      for (var i = 0; i < chunks.length; i++) {
        buffer.write('${i + 1}. ${chunks[i].text}');
        if (i < chunks.length - 1) {
          buffer.write(' //\n');
        }
      }
      textToCopy = buffer.toString().trim();
    } else {
      textToCopy = turn.rawText.trim();
    }

    Clipboard.setData(ClipboardData(text: textToCopy));
    if (!mounted) return;
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _viewMode == TranscriptViewMode.senseGroup
              ? '已复制意群断句排版文本（可供 AI 评估停顿划分）'
              : '已复制发言文本（纯英文）',
          style: const TextStyle(fontSize: 12),
        ),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        width: 330,
      ),
    );
  }

  Widget _buildTurnContent(
    int turnIndex,
    SpeakerTurn turn,
    bool isActive,
    Color textPrimary,
    Color textSecondary,
    Color accent,
    bool isDark,
  ) {
    switch (_viewMode) {
      case TranscriptViewMode.standard:
        return SelectableText.rich(
          TermHighlighter.highlight(
            turn.rawText,
            active: accent,
            base: textPrimary,
          ),
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: textPrimary,
          ),
        );

      case TranscriptViewMode.senseGroup:
        final chunks = SenseGroupChunker.chunk(turn.rawText);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var cIdx = 0; cIdx < chunks.length; cIdx++) ...[
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 1.5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${cIdx + 1}. ',
                      style: TextStyle(
                        fontSize: 10,
                        color: accent.withValues(alpha: 0.8),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Expanded(
                      child: SelectableText.rich(
                        ConnectedSpeechMarker.buildSpans(
                          text: chunks[cIdx].text,
                          normalColor: textPrimary,
                          accentColor: accent,
                          weakColor: textSecondary.withValues(alpha: 0.6),
                          fontSize: 12,
                        ),
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: textPrimary,
                        ),
                      ),
                    ),
                    if (cIdx < chunks.length - 1)
                      Text(
                        ' //',
                        style: TextStyle(
                          fontSize: 11,
                          color: accent.withValues(alpha: 0.6),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );

      case TranscriptViewMode.blindMask:
        final isRevealed = _revealedTurns.contains(turnIndex);
        if (!isRevealed) {
          return InkWell(
            onTap: () {
              setState(() {
                _revealedTurns.add(turnIndex);
              });
            },
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isDark ? Colors.white12 : Colors.black12,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.visibility_off_outlined,
                    size: 13,
                    color: textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '•••••••••••••••• (盲听模式 · 点击翻开原文)',
                      style: TextStyle(
                        fontSize: 11,
                        color: textSecondary.withValues(alpha: 0.8),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        } else {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText.rich(
                  TermHighlighter.highlight(
                    turn.rawText,
                    active: accent,
                    base: textPrimary,
                  ),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: textPrimary,
                  ),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                tooltip: '重新遮罩',
                icon: Icon(
                  Icons.visibility_outlined,
                  size: 13,
                  color: textSecondary,
                ),
                onPressed: () {
                  setState(() {
                    _revealedTurns.remove(turnIndex);
                  });
                },
              ),
            ],
          );
        }
    }
  }

  void _openSaveVaultDialog(Clip clip, int turnIndex, SpeakerTurn turn) {
    final existing = SentenceVaultStore.instance.find(clip.id, turnIndex);
    final selectedTags = <String>{
      if (existing != null) ...existing.tags else ...[VaultTags.complexClause],
    };

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = context.isDarkMode;
            final border =
                isDark ? context.borderSubtle : AppTheme.lightBorderSubtle;
            final textPrimary =
                isDark ? context.textPrimary : AppTheme.lightTextPrimary;
            final textSecondary =
                isDark ? context.textSecondary : AppTheme.lightTextSecondary;
            final accent = context.accentText;

            return AlertDialog(
              backgroundColor: isDark ? context.bgCard : AppTheme.lightBgCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
                side: BorderSide(color: border),
              ),
              title: Row(
                children: [
                  const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    existing != null ? '管理长难句' : '摘录至长难句复盘本',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: textPrimary,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${turn.speaker} 发言：',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.black26 : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        turn.rawText,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: textPrimary),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '选择难点标签（便于后续分类突破）：',
                      style: TextStyle(fontSize: 11, color: textSecondary),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in VaultTags.defaults) ...[
                          FilterChip(
                            label: Text(tag, style: const TextStyle(fontSize: 11)),
                            selected: selectedTags.contains(tag),
                            selectedColor: accent.withValues(alpha: 0.20),
                            checkmarkColor: accent,
                            onSelected: (val) {
                              setDialogState(() {
                                if (val) {
                                  selectedTags.add(tag);
                                } else {
                                  selectedTags.remove(tag);
                                }
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                if (existing != null)
                  TextButton(
                    style: TextButton.styleFrom(foregroundColor: Colors.red),
                    onPressed: () async {
                      await SentenceVaultStore.instance.remove(existing.id);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('移出难句本'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final item = VaultSentence(
                      id: existing?.id ?? '${clip.id}_$turnIndex',
                      clipId: clip.id,
                      meetingTitle: clip.title,
                      scene: clip.scene,
                      turnIndex: turnIndex,
                      speaker: turn.speaker,
                      role: turn.role,
                      text: turn.rawText,
                      startMs: turn.startMs,
                      endMs: turn.endMs,
                      tags: selectedTags.toList(),
                      mastered: existing?.mastered ?? false,
                      reviewCount: existing?.reviewCount ?? 0,
                      createdAt: existing?.createdAt ?? DateTime.now(),
                      updatedAt: DateTime.now(),
                    );
                    await SentenceVaultStore.instance.addOrUpdate(item);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  child: Text(existing != null ? '更新' : '保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCollectTermButton(
    Clip clip,
    SpeakerTurn turn,
    Color textSecondary,
  ) {
    final terms = TermHighlighter.extractTerms(turn.rawText);
    if (terms.isEmpty) return const SizedBox.shrink();
    return Tooltip(
      message: '收藏术语：${terms.take(3).join('、')}',
      child: IconButton(
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
        icon: Icon(Icons.bookmark_add_outlined, size: 14, color: textSecondary),
        onPressed: () => widget.onCollectTerm(clip, turn, terms.first),
      ),
    );
  }
}
