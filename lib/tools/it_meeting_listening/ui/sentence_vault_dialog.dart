import 'package:flutter/material.dart';

import '../../../theme/app_theme.dart';
import '../models/sentence_vault_models.dart';
import '../services/connected_speech_marker.dart';
import '../services/listening_player_controller.dart';
import '../services/sense_group_chunker.dart';
import '../services/sentence_vault_store.dart';

/// 长难句复盘本（Sentence Vault）对话框
class SentenceVaultDialog extends StatefulWidget {
  final ListeningPlayerController? player;
  final void Function(VaultSentence sentence)? onJumpToMeeting;

  const SentenceVaultDialog({
    super.key,
    this.player,
    this.onJumpToMeeting,
  });

  @override
  State<SentenceVaultDialog> createState() => _SentenceVaultDialogState();
}

class _SentenceVaultDialogState extends State<SentenceVaultDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  final Set<String> _revealedSentenceIds = {};
  final Set<String> _showSenseGroupIds = {};

  String _searchQuery = '';
  String? _selectedTag;
  bool? _masteredFilter; // null = 全部, false = 待攻克, true = 已掌握

  @override
  void initState() {
    super.initState();
    SentenceVaultStore.instance.init();
    SentenceVaultStore.instance.addListener(_onStoreChanged);
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text;
      });
    });
  }

  @override
  void dispose() {
    SentenceVaultStore.instance.removeListener(_onStoreChanged);
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final store = SentenceVaultStore.instance;
    final isDark = context.isDarkMode;
    final bgCard = isDark ? context.bgCard : AppTheme.lightBgCard;
    final border = isDark ? context.borderSubtle : AppTheme.lightBorderSubtle;
    final textPrimary =
        isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? context.textSecondary : AppTheme.lightTextSecondary;
    final accent = context.accentText;

    final items = store.filter(
      query: _searchQuery,
      tag: _selectedTag,
      mastered: _masteredFilter,
    );

    return Dialog(
      backgroundColor: bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 900,
          maxHeight: 740,
          minWidth: 640,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶栏
            _buildHeader(context, store, textPrimary, textSecondary, accent, border),
            // 过滤与搜索工具栏
            _buildFilterBar(context, textPrimary, textSecondary, accent, border),
            // 列表内容
            Expanded(
              child: items.isEmpty
                  ? _buildEmptyState(textSecondary, accent)
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: items.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        return _buildSentenceCard(
                          context,
                          items[index],
                          isDark,
                          border,
                          textPrimary,
                          textSecondary,
                          accent,
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    SentenceVaultStore store,
    Color textPrimary,
    Color textSecondary,
    Color accent,
    Color border,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 14, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.star_rounded,
              color: Colors.amber,
              size: 20,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '长难句复盘本 (Sentence Vault)',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '待攻克: ${store.unmasteredCount}  |  已掌握: ${store.masteredCount}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: accent,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '断句抓主干 · 辅元连读/弱读标识 · 影子跟读复述',
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '关闭',
            icon: Icon(Icons.close_rounded, size: 20, color: textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(
    BuildContext context,
    Color textPrimary,
    Color textSecondary,
    Color accent,
    Color border,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 状态筛选分段
              _buildFilterChip('全部', _masteredFilter == null, () {
                setState(() => _masteredFilter = null);
              }, accent),
              const SizedBox(width: 6),
              _buildFilterChip('待攻克', _masteredFilter == false, () {
                setState(() => _masteredFilter = false);
              }, accent),
              const SizedBox(width: 6),
              _buildFilterChip('已掌握', _masteredFilter == true, () {
                setState(() => _masteredFilter = true);
              }, accent),
              const SizedBox(width: 16),
              // 搜索框
              Expanded(
                child: SizedBox(
                  height: 32,
                  child: TextField(
                    controller: _searchCtrl,
                    style: TextStyle(fontSize: 12, color: textPrimary),
                    decoration: InputDecoration(
                      hintText: '搜索难句、发言人、会议名称...',
                      hintStyle: TextStyle(fontSize: 12, color: textSecondary),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        size: 16,
                        color: textSecondary,
                      ),
                      contentPadding: EdgeInsets.zero,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: border),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(6),
                        borderSide: BorderSide(color: border),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 标签快捷筛选
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                Text(
                  '标签：',
                  style: TextStyle(fontSize: 11, color: textSecondary),
                ),
                _buildTagFilterChip('全部标签', _selectedTag == null, () {
                  setState(() => _selectedTag = null);
                }, accent),
                for (final tag in VaultTags.defaults) ...[
                  const SizedBox(width: 4),
                  _buildTagFilterChip(tag, _selectedTag == tag, () {
                    setState(() {
                      _selectedTag = (_selectedTag == tag) ? null : tag;
                    });
                  }, accent),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(
    String label,
    bool isSelected,
    VoidCallback onTap,
    Color accent,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? accent : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? accent : null,
          ),
        ),
      ),
    );
  }

  Widget _buildTagFilterChip(
    String label,
    bool isSelected,
    VoidCallback onTap,
    Color accent,
  ) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: isSelected ? accent : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? accent : Colors.grey.withValues(alpha: 0.3),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isSelected ? Colors.white : null,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(Color textSecondary, Color accent) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.auto_stories_outlined, size: 48, color: textSecondary),
          const SizedBox(height: 12),
          Text(
            '尚未收藏长难句',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: textSecondary),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Text(
              '在右侧精听抽屉中，点击发言条目右侧的 ⭐，即可将听不懂、跟不上的长句一键收藏到此处。\n使用「意群拆解」与「单句死循环」集中攻克！',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: textSecondary.withValues(alpha: 0.8), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentenceCard(
    BuildContext context,
    VaultSentence sentence,
    bool isDark,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    final isRevealed = _revealedSentenceIds.contains(sentence.id);
    final showSenseGroup = _showSenseGroupIds.contains(sentence.id);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? context.bgCardHover : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: sentence.mastered
              ? Colors.green.withValues(alpha: 0.4)
              : border,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 卡片头
          Row(
            children: [
              Text(
                '${sentence.speaker}${sentence.role.isNotEmpty ? ' (${sentence.role})' : ''}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '·  ${sentence.meetingTitle}',
                style: TextStyle(fontSize: 11, color: textSecondary),
              ),
              const Spacer(),
              // 掌握状态勾选
              InkWell(
                onTap: () => SentenceVaultStore.instance.toggleMastered(sentence.id),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  child: Row(
                    children: [
                      Icon(
                        sentence.mastered
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 15,
                        color: sentence.mastered ? Colors.green : textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        sentence.mastered ? '已掌握' : '标记已掌握',
                        style: TextStyle(
                          fontSize: 11,
                          color: sentence.mastered ? Colors.green : textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 删除
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                icon: Icon(Icons.delete_outline_rounded, size: 15, color: textSecondary),
                tooltip: '移出复盘本',
                onPressed: () => SentenceVaultStore.instance.remove(sentence.id),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 句子正文展示区（支持盲听遮罩与意群拆解）
          if (!isRevealed)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.black26 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: border,
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.visibility_off_outlined, size: 16, color: textSecondary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '【盲听遮罩中】请先用耳朵抓取主干信息（谁+做什么）',
                      style: TextStyle(fontSize: 12, color: textSecondary),
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: const Icon(Icons.visibility_rounded, size: 13),
                    label: const Text('翻开原文', style: TextStyle(fontSize: 11)),
                    onPressed: () {
                      setState(() {
                        _revealedSentenceIds.add(sentence.id);
                      });
                    },
                  ),
                ],
              ),
            )
          else ...[
            if (showSenseGroup)
              // 意群分块断句视图
              _buildSenseGroupView(sentence.text, textPrimary, textSecondary, accent, isDark)
            else
              // 标准富文本视图（带连读与弱读标记）
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isDark ? Colors.black12 : Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: SelectableText.rich(
                  ConnectedSpeechMarker.buildSpans(
                    text: sentence.text,
                    normalColor: textPrimary,
                    accentColor: accent,
                    weakColor: textSecondary.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
              ),
          ],
          const SizedBox(height: 8),
          // 底部控制与标签栏
          Row(
            children: [
              // 标签列表
              for (final t in sentence.tags) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    t,
                    style: TextStyle(fontSize: 10, color: accent),
                  ),
                ),
                const SizedBox(width: 4),
              ],
              const Spacer(),
              // 视图切换（意群 / 完整）
              if (isRevealed)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  icon: Icon(
                    showSenseGroup
                        ? Icons.notes_rounded
                        : Icons.format_line_spacing_rounded,
                    size: 14,
                  ),
                  label: Text(
                    showSenseGroup ? '紧凑排版' : '意群断句',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () {
                    setState(() {
                      if (showSenseGroup) {
                        _showSenseGroupIds.remove(sentence.id);
                      } else {
                        _showSenseGroupIds.add(sentence.id);
                      }
                    });
                  },
                ),
              // 重新遮罩
              if (isRevealed)
                IconButton(
                  visualDensity: VisualDensity.compact,
                  tooltip: '遮罩盲听',
                  icon: Icon(Icons.visibility_off_outlined, size: 14, color: textSecondary),
                  onPressed: () {
                    setState(() {
                      _revealedSentenceIds.remove(sentence.id);
                    });
                  },
                ),
              const SizedBox(width: 4),
              // 播放/单句循环跟读按钮
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                icon: const Icon(Icons.repeat_one_rounded, size: 14),
                label: Text(
                  '跟读循环 (${sentence.reviewCount})',
                  style: const TextStyle(fontSize: 11),
                ),
                onPressed: () async {
                  await SentenceVaultStore.instance.incrementReviewCount(sentence.id);
                  if (widget.player != null) {
                    await widget.player!.seek(sentence.startMs);
                    widget.player!.setLoopingTurn(sentence.turnIndex);
                    if (!widget.player!.isPlaying) {
                      await widget.player!.resume();
                    }
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSenseGroupView(
    String text,
    Color textPrimary,
    Color textSecondary,
    Color accent,
    bool isDark,
  ) {
    final chunks = SenseGroupChunker.chunk(text);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black26 : Colors.blue.shade50.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < chunks.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${i + 1}. ',
                    style: TextStyle(
                      fontSize: 11,
                      color: accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Expanded(
                    child: SelectableText.rich(
                      ConnectedSpeechMarker.buildSpans(
                        text: chunks[i].text,
                        normalColor: textPrimary,
                        accentColor: accent,
                        weakColor: textSecondary.withValues(alpha: 0.6),
                        fontSize: 13,
                      ),
                    ),
                  ),
                  if (i < chunks.length - 1)
                    Text(
                      ' //',
                      style: TextStyle(
                        fontSize: 12,
                        color: accent.withValues(alpha: 0.6),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
