/// 全局精听右侧抽屉与逐句文稿视图（Group 9.2）。
///
/// 布局：
/// - 宽屏（>= 960px）下作为右侧推挤栏（宽 420px）展开；
/// - 窄屏（< 960px）下作为右侧浮层覆盖展开；
/// - 始终跟随当前正在播放的 `Clip`；
/// - 默认收起，开始播放新条目不会自动展开；
/// - 真实会议的“插入我的回答（💬）”与“已插入回答的操作（⋯）”在抽屉内完成。
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../../theme/app_theme.dart';
import '../models/listening_models.dart';
import '../models/real_meeting_models.dart';
import '../services/term_highlighter.dart';

class TranscriptDrawer extends StatefulWidget {
  final Clip? clip;
  final int currentTurnIndex;
  final VoidCallback onClose;
  final ValueChanged<int> onSeekToTurn;
  final void Function(Clip clip, SpeakerTurn turn, String term) onCollectTerm;
  final ValueChanged<int> onOpenAnswerComposer;
  final ValueChanged<SpeakerTurn> onOpenAnswerActions;

  const TranscriptDrawer({
    super.key,
    required this.clip,
    required this.currentTurnIndex,
    required this.onClose,
    required this.onSeekToTurn,
    required this.onCollectTerm,
    required this.onOpenAnswerComposer,
    required this.onOpenAnswerActions,
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
  bool _userInteracted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.currentTurnIndex >= 0) {
        _scrollToTurn(widget.currentTurnIndex, animated: false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant TranscriptDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    final clipChanged = oldWidget.clip?.id != widget.clip?.id;
    if (clipChanged) {
      _userInteracted = false;
      _itemKeys.clear();
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
    _scrollController.dispose();
    super.dispose();
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
      width: 420,
      decoration: BoxDecoration(
        color: bgCard,
        border: Border(left: BorderSide(color: border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 抽屉顶栏
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 10, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: border)),
            ),
            child: Row(
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
                      if (activeClip != null && activeClip.summary.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            activeClip.summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: 11, color: textSecondary),
                          ),
                        ),
                    ],
                  ),
                ),
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

                            return Container(
                              key: itemKey,
                              margin: const EdgeInsets.only(bottom: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: active
                                    ? accent.withValues(alpha: 0.10)
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: InkWell(
                                onTap: isMeeting
                                    ? () => widget.onSeekToTurn(turn.startMs)
                                    : null,
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SizedBox(
                                      width: 108,
                                      child: Text(
                                        isMeeting
                                            ? '${turn.speaker}${isAnswer ? ' · 我的回答' : ''}:'
                                            : turn.displayName,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color:
                                              active ? accent : textSecondary,
                                          fontWeight: isMeeting
                                              ? FontWeight.w600
                                              : FontWeight.normal,
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: RichText(
                                        text: TermHighlighter.highlight(
                                          turn.rawText,
                                          active: accent,
                                          base: textPrimary,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
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
