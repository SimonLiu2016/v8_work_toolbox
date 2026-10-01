import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../services/settings_store.dart';
import '../../../theme/app_theme.dart';
import '../../lookup_panel/services/dictionary_service.dart';
import '../../notebook/note_store.dart';
import '../models/vocab_entry.dart';
import '../services/vocab_store.dart';

/// 生词词条的「列表展示签名」。
///
/// 刻意**不是**全字段：列表只展示 word / 词性缩写 / `definitions.first` /
/// 掌握程度 / 标签，筛选栏另外展示按 mastery 与 tag 的计数。
/// `phrases`、`examples`、`audioUrl`、`addedAt` 不在列表里，把它们算进签名
/// 会让一次无谓的外部改动触发重建 —— 用户看到的就是列表白闪一下。
///
/// `definitions.first` 而不是整份 definitions：第二条释义进来，列表看起来
/// 一模一样，不该闪。
@visibleForTesting
String vocabEntrySignature(VocabEntryModel e) {
  return [
    e.id,
    e.word,
    e.partOfSpeech ?? '',
    e.definitions.isEmpty ? '' : e.definitions.first,
    e.masteryLevel,
    e.tags.join('\u0000'),
  ].join('\u0001');
}

/// 两份词条列表的展示内容是否不同。
///
/// 聚焦刷新靠它决定要不要 `setState`：返回 false 就什么都不做。少了这一层，
/// 每次窗口获得焦点都会重建一次列表——用户看到的是闪烁。
/// 标签集合是否一致。顺序无关——筛选栏按 `allTags()` 的次序展示，
/// 内容相同就不该为它重建。
bool _sameTags(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final sa = Set<String>.from(a);
  return sa.length == b.toSet().length && sa.containsAll(b.toSet());
}

@visibleForTesting
bool vocabListChanged(
  List<VocabEntryModel> before,
  List<VocabEntryModel> after,
) {
  if (before.length != after.length) return true;
  for (var i = 0; i < before.length; i++) {
    if (vocabEntrySignature(before[i]) != vocabEntrySignature(after[i])) {
      return true;
    }
  }
  return false;
}

/// 把「窗口获得焦点」转发成一次回调。
///
/// `WindowListener` 在 window_manager 0.5.x 里是**抽象类**而不是 mixin，
/// 所以 State 不能 `with` 它；用一个只覆写 onWindowFocus 的薄壳转接，
/// 比把整个 State 改成继承它干净。
class _WindowFocusRelay extends WindowListener {
  _WindowFocusRelay(this._onFocus);

  final VoidCallback _onFocus;

  @override
  void onWindowFocus() => _onFocus();
}

/// 生词本主页面
class VocabBookPage extends StatefulWidget {
  const VocabBookPage({super.key});

  @override
  State<VocabBookPage> createState() => _VocabBookPageState();
}

class _VocabBookPageState extends State<VocabBookPage> {
  late final _WindowFocusRelay _focusRelay = _WindowFocusRelay(_onWindowFocus);
  final VocabStore _store = VocabStore.instance;
  final AudioPlayer _audioPlayer = AudioPlayer();

  List<VocabEntryModel> _entries = [];
  List<String> _tags = [];
  VocabEntryModel? _selectedEntry;

  String _searchQuery = '';
  int? _selectedMastery; // null = 全部
  String? _selectedTag; // null = 全部
  bool _isLoading = true;

  // 批量模式
  bool _isBatchMode = false;
  final Set<String> _selectedIds = {};

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    windowManager.addListener(_focusRelay);
    _loadData();
  }

  @override
  void dispose() {
    windowManager.removeListener(_focusRelay);
    _audioPlayer.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 窗口重新获得焦点时重新查库。
  ///
  /// 为什么需要：生词本可能被**其他进程**改过——浏览器伴侣浮窗、独立的查词
  /// 窗口都是 desktop_multi_window 起的独立进程，写的是同一个 SQLite 库。
  /// `VocabStore` 不是 ChangeNotifier，且 ChangeNotifier 本来也跨不了进程；
  /// 「用户切回窗口」是唯一免费可得的"该刷新了"信号。
  ///
  /// 走 [_loadData]（全量查询）而非按筛选重查：_loadData 拿全量后
  /// _filteredEntries 会按当前筛选重新过滤，结果与"按筛选查询"等价，
  /// 且不会把用户已应用的筛选冲掉。
  void _onWindowFocus() {
    if (_isLoading) return; // 首次加载未完成，不并发再起一次
    _loadData(silent: true);
  }

  Future<void> _loadData({bool silent = false}) async {
    if (silent) {
      // 聚焦刷新：不显示 loading、不清空列表。用户切回窗口时列表必须原样
      // 在那儿，内容变了就地更新——闪一下比不刷新更烦。
      final all = await _store.queryAll();
      final tags = await _store.allTags();
      if (!mounted) return;
      if (!vocabListChanged(_entries, all) && _sameTags(_tags, tags)) {
        return; // 没变化：什么都不做
      }
      setState(() {
        _entries = all;
        _tags = tags;
        if (_selectedEntry != null) {
          // 选中项按 id 跟踪：刷新后仍在同一条上（它可能刚被别处改过）。
          final found = all.where((e) => e.id == _selectedEntry!.id);
          _selectedEntry =
              found.isNotEmpty ? found.first : (all.isNotEmpty ? all.first : null);
        } else if (all.isNotEmpty) {
          _selectedEntry = all.first;
        }
      });
      return;
    }

    setState(() => _isLoading = true);
    final all = await _store.queryAll();
    final tags = await _store.allTags();
    if (!mounted) return;

    setState(() {
      _entries = all;
      _tags = tags;
      _isLoading = false;
      if (_selectedEntry != null) {
        final found = all.where((e) => e.id == _selectedEntry!.id);
        _selectedEntry = found.isNotEmpty ? found.first : (all.isNotEmpty ? all.first : null);
      } else if (all.isNotEmpty) {
        _selectedEntry = all.first;
      }
    });
  }

  List<VocabEntryModel> get _filteredEntries {
    return _entries.where((e) {
      if (_selectedMastery != null && e.masteryLevel != _selectedMastery) {
        return false;
      }
      if (_selectedTag != null && !e.tags.contains(_selectedTag)) {
        return false;
      }
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchWord = e.word.toLowerCase().contains(q);
        final matchDef = e.definitions.any((d) => d.toLowerCase().contains(q));
        return matchWord || matchDef;
      }
      return true;
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // 播放发音
  // ---------------------------------------------------------------------------

  Future<void> _playAudio(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      debugPrint('[VocabBook] Play audio failed: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 添加词条对话框
  // ---------------------------------------------------------------------------

  Future<void> _showAddEntryDialog() async {
    final wordController = TextEditingController();
    final phoneticController = TextEditingController();
    final defController = TextEditingController();
    final exampleController = TextEditingController();
    String? audioUrl;
    String? partOfSpeech;
    bool isSearching = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            title: const Text('添加生词 / 短语'),
            content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: wordController,
                            autofocus: true,
                            decoration: const InputDecoration(
                              labelText: '单词或短语',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: isSearching
                              ? null
                              : () async {
                                  final w = wordController.text.trim();
                                  if (w.isEmpty) return;
                                  setDlgState(() => isSearching = true);
                                  final dict = await DictionaryService.lookup(w);
                                  setDlgState(() {
                                    isSearching = false;
                                    if (dict != null) {
                                      phoneticController.text = dict.phonetic ?? '';
                                      audioUrl = dict.audioUrl;
                                      partOfSpeech = dict.primaryPartOfSpeech;
                                      defController.text = dict.allDefinitions.take(3).join('\n');
                                      exampleController.text = dict.allExamples.take(2).join('\n');
                                    }
                                  });
                                },
                          child: isSearching
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('查询词典'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneticController,
                      decoration: const InputDecoration(
                        labelText: '音标（可选）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: defController,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: '释义（每行一条）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: exampleController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: '例句（可选，每行一条）',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () async {
                  final word = wordController.text.trim();
                  if (word.isEmpty) return;
                  final defs = defController.text
                      .split('\n')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();
                  final examples = exampleController.text
                      .split('\n')
                      .map((s) => s.trim())
                      .where((s) => s.isNotEmpty)
                      .toList();

                  await _store.insertFromDictionary(
                    word: word,
                    phonetic: phoneticController.text.trim().isEmpty ? null : phoneticController.text.trim(),
                    audioUrl: audioUrl,
                    partOfSpeech: partOfSpeech,
                    definitions: defs,
                    examples: examples,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  _loadData();
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 生词本设置面板
  // ---------------------------------------------------------------------------

  Future<void> _showSettingsDialog() async {
    final notebooks = await NoteStore.instance.allNotebooks();
    final cfg = await SettingsStore.instance.readToolConfig('vocab-book');
    String? currentDefaultId = cfg['vocabDefaultNotebookId'] as String?;

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          return AlertDialog(
            title: const Text('生词本设置'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('词条导出至默认笔记本：', style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: currentDefaultId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: notebooks
                        .map(
                          (nb) => DropdownMenuItem(
                            value: nb.id,
                            child: Text('${nb.icon} ${nb.name}'),
                          ),
                        )
                        .toList(),
                    onChanged: (val) => setDlgState(() => currentDefaultId = val),
                    hint: const Text('选择目标笔记本'),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
              FilledButton(
                onPressed: () async {
                  cfg['vocabDefaultNotebookId'] = currentDefaultId;
                  await SettingsStore.instance.writeToolConfig('vocab-book', cfg);
                  if (ctx.mounted) {
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('已保存生词本默认笔记本设置')),
                    );
                  }
                },
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 删除操作
  // ---------------------------------------------------------------------------

  Future<void> _deleteEntry(String id) async {
    await _store.deleteEntry(id);
    _loadData();
  }

  Future<void> _batchDelete() async {
    if (_selectedIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('批量删除'),
        content: Text('确定删除选中的 ${_selectedIds.length} 个词条吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: context.errorSolid),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _store.deleteEntries(_selectedIds.toList());
    _selectedIds.clear();
    _isBatchMode = false;
    _loadData();
  }

  // ---------------------------------------------------------------------------
  // UI 构建
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgWindow,
      body: Row(
        children: [
          // 左侧：筛选侧边栏 (200px)
          _buildSidebar(),
          VerticalDivider(width: 1, color: context.borderSubtle),

          // 中间：词条列表 (280px)
          _buildListPanel(),
          VerticalDivider(width: 1, color: context.borderSubtle),

          // 右侧：词条详情 (自适应填充)
          Expanded(child: _buildDetailPanel()),
        ],
      ),
    );
  }

  // 1. 侧边栏
  Widget _buildSidebar() {
    return Container(
      width: 200,
      color: context.bgSidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部栏
          Container(
            height: 48,
            padding: EdgeInsets.symmetric(horizontal: 12),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(Icons.menu_book_rounded, size: 18, color: context.accentText),
                SizedBox(width: 8),
                Text(
                  '生词本',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: context.textPrimary),
                ),
                Spacer(),
                IconButton(
                  icon: Icon(Icons.settings_outlined, size: 16, color: context.textTertiary),
                  tooltip: '设置',
                  onPressed: _showSettingsDialog,
                ),
              ],
            ),
          ),
          Divider(height: 1, color: context.borderSubtle),

          // 全部
          ListTile(
            dense: true,
            leading: Icon(Icons.all_inbox_rounded, size: 16),
            title: Text('全部词条', style: TextStyle(fontSize: 13)),
            trailing: Text('${_entries.length}', style: TextStyle(fontSize: 11, color: context.textTertiary)),
            selected: _selectedMastery == null && _selectedTag == null,
            selectedTileColor: context.bgSelected,
            onTap: () => setState(() {
              _selectedMastery = null;
              _selectedTag = null;
            }),
          ),

          // 掌握程度筛选
          Padding(
            padding: EdgeInsets.only(left: 12, top: 12, bottom: 4),
            child: Text(
              '掌握程度',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.textTertiary),
            ),
          ),
          ...List.generate(6, (idx) {
            final color = Color(VocabEntryModel.masteryColors[idx]);
            final count = _entries.where((e) => e.masteryLevel == idx).length;
            return ListTile(
              dense: true,
              leading: Icon(Icons.circle, size: 10, color: color),
              title: Text(VocabEntryModel.masteryLabels[idx], style: TextStyle(fontSize: 12.5)),
              trailing: Text('$count', style: TextStyle(fontSize: 11, color: context.textTertiary)),
              selected: _selectedMastery == idx,
              selectedTileColor: context.bgSelected,
              onTap: () => setState(() {
                _selectedMastery = idx;
                _selectedTag = null;
              }),
            );
          }),

          // 标签筛选
          if (_tags.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.only(left: 12, top: 12, bottom: 4),
              child: Text(
                '标签',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.textTertiary),
              ),
            ),
            Expanded(
              child: ListView(
                children: _tags.map((tag) {
                  final count = _entries.where((e) => e.tags.contains(tag)).length;
                  return ListTile(
                    dense: true,
                    leading: Icon(Icons.label_outline, size: 14),
                    title: Text(tag, style: TextStyle(fontSize: 12.5)),
                    trailing: Text('$count', style: TextStyle(fontSize: 11, color: context.textTertiary)),
                    selected: _selectedTag == tag,
                    selectedTileColor: context.bgSelected,
                    onTap: () => setState(() {
                      _selectedTag = tag;
                      _selectedMastery = null;
                    }),
                  );
                }).toList(),
              ),
            ),
          ] else
            const Spacer(),
        ],
      ),
    );
  }

  // 2. 词条列表
  Widget _buildListPanel() {
    final list = _filteredEntries;

    return SizedBox(
      width: 280,
      child: Column(
        children: [
          // 搜索与工具栏
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.bgContent,
              border: Border(bottom: BorderSide(color: context.borderSubtle)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 32,
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: '搜索词条或释义…',
                            hintStyle: TextStyle(fontSize: 12),
                            prefixIcon: Icon(Icons.search, size: 16),
                            filled: true,
                            fillColor: context.bgInput,
                            contentPadding: EdgeInsets.zero,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: BorderSide.none,
                            ),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v.trim()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filledTonal(
                      icon: const Icon(Icons.add, size: 16),
                      tooltip: '添加词条',
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        padding: EdgeInsets.all(6),
                      ),
                      onPressed: _showAddEntryDialog,
                    ),
                  ],
                ),
                SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${list.length} 个词条',
                      style: TextStyle(fontSize: 11, color: context.textTertiary),
                    ),
                    const Spacer(),
                    InkWell(
                      onTap: () => setState(() {
                        _isBatchMode = !_isBatchMode;
                        _selectedIds.clear();
                      }),
                      child: Text(
                        _isBatchMode ? '取消选择' : '批量操作',
                        style: TextStyle(fontSize: 11, color: context.accentText),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 列表主体
          Expanded(
            child: _isLoading
                ? Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? Center(
                        child: Text('暂无词条', style: TextStyle(color: context.textTertiary)),
                      )
                    : ListView.builder(
                        itemCount: list.length,
                        itemBuilder: (ctx, index) {
                          final item = list[index];
                          final isSelected = _selectedEntry?.id == item.id;
                          final masteryColor = Color(VocabEntryModel.masteryColors[item.masteryLevel]);

                          return InkWell(
                            onTap: () {
                              if (_isBatchMode) {
                                setState(() {
                                  if (_selectedIds.contains(item.id)) {
                                    _selectedIds.remove(item.id);
                                  } else {
                                    _selectedIds.add(item.id);
                                  }
                                });
                              } else {
                                setState(() => _selectedEntry = item);
                              }
                            },
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSelected ? context.bgSelected : Colors.transparent,
                                border: Border(bottom: BorderSide(color: context.borderSubtle)),
                              ),
                              child: Row(
                                children: [
                                  if (_isBatchMode)
                                    Checkbox(
                                      value: _selectedIds.contains(item.id),
                                      onChanged: (v) => setState(() {
                                        if (v == true) {
                                          _selectedIds.add(item.id);
                                        } else {
                                          _selectedIds.remove(item.id);
                                        }
                                      }),
                                    )
                                  else
                                    Container(
                                      width: 6,
                                      height: 6,
                                      decoration: BoxDecoration(
                                        color: masteryColor,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              item.word,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: isSelected ? context.accentText : context.textPrimary,
                                              ),
                                            ),
                                            if (item.partOfSpeech != null && item.partOfSpeech!.isNotEmpty) ...[
                                              SizedBox(width: 4),
                                              Text(
                                                item.partOfSpeechAbbr,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: context.textTertiary,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (item.definitions.isNotEmpty)
                                          Text(
                                            item.definitions.first,
                                            style: TextStyle(fontSize: 11.5, color: context.textSecondary),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert, size: 14, color: context.textTertiary),
                                    padding: EdgeInsets.zero,
                                    onSelected: (v) {
                                      if (v == 'delete') _deleteEntry(item.id);
                                    },
                                    itemBuilder: (ctx) => [
                                      PopupMenuItem(
                                        value: 'delete',
                                        child: Text('删除', style: TextStyle(color: context.errorText)),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),

          // 批量操作底部栏
          if (_isBatchMode)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              color: context.bgCard,
              child: Row(
                children: [
                  Text('已选 ${_selectedIds.length} 项', style: const TextStyle(fontSize: 12)),
                  const Spacer(),
                  FilledButton(
                    onPressed: _selectedIds.isEmpty ? null : _batchDelete,
                    style: FilledButton.styleFrom(backgroundColor: context.errorSolid),
                    child: const Text('删除所选'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 3. 词条详情
  Widget _buildDetailPanel() {
    final entry = _selectedEntry;
    if (entry == null) {
      return Center(
        child: Text('选择左侧词条查看详情', style: TextStyle(color: context.textTertiary)),
      );
    }

    return Container(
      color: context.bgContent,
      padding: EdgeInsets.all(24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 词头行
            Row(
              children: [
                Text(
                  entry.word,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: context.textPrimary),
                ),
                if (entry.phonetic != null && entry.phonetic!.isNotEmpty) ...[
                  SizedBox(width: 12),
                  Text(
                    entry.phonetic!,
                    style: TextStyle(fontSize: 16, color: context.textSecondary),
                  ),
                ],
                if (entry.audioUrl != null && entry.audioUrl!.isNotEmpty) ...[
                  SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.volume_up_rounded, color: context.accentText),
                    tooltip: '朗读发音',
                    onPressed: () => _playAudio(entry.audioUrl),
                  ),
                ],
                Spacer(),
                // 掌握程度调节器
                _buildMasteryPicker(entry),
              ],
            ),
            SizedBox(height: 16),
            Divider(color: context.borderSubtle),
            SizedBox(height: 16),

            // 释义
            if (entry.definitions.isNotEmpty) ...[
              Text('释义', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: context.textPrimary)),
              SizedBox(height: 8),
              ...entry.definitions.map(
                (d) => Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: TextStyle(color: context.accentText)),
                      Expanded(child: Text(d, style: TextStyle(fontSize: 13.5, color: context.textSecondary))),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 16),
            ],

            // 例句
            if (entry.examples.isNotEmpty) ...[
              Text('例句', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: context.textPrimary)),
              SizedBox(height: 8),
              ...entry.examples.map(
                (e) => Container(
                  margin: EdgeInsets.only(bottom: 8),
                  padding: EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: context.bgCard,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: context.borderSubtle),
                  ),
                  child: Text(e, style: TextStyle(fontSize: 13, color: context.textPrimary, fontStyle: FontStyle.italic)),
                ),
              ),
              SizedBox(height: 16),
            ],

            // 来源上下文
            if (entry.sourceContext != null && entry.sourceContext!.isNotEmpty) ...[
              Text('来源上下文', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: context.textPrimary)),
              SizedBox(height: 8),
              Container(
                padding: EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: context.bgCard,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: context.borderSubtle),
                ),
                child: Text(entry.sourceContext!, style: TextStyle(fontSize: 12.5, color: context.textSecondary)),
              ),
              SizedBox(height: 16),
            ],

            // 标签
            Row(
              children: [
                Icon(Icons.label_outline, size: 16, color: context.textTertiary),
                SizedBox(width: 8),
                Text(
                  entry.tags.isEmpty ? '无标签' : entry.tags.join(', '),
                  style: TextStyle(fontSize: 12, color: context.textTertiary),
                ),
                Spacer(),
                Text(
                  '添加于: ${entry.addedAt.year}-${entry.addedAt.month.toString().padLeft(2, '0')}-${entry.addedAt.day.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 11, color: context.textTertiary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMasteryPicker(VocabEntryModel entry) {
    return Row(
      children: [
        Text('掌握度: ', style: TextStyle(fontSize: 12, color: context.textTertiary)),
        ...List.generate(6, (idx) {
          final isSelected = entry.masteryLevel == idx;
          final color = Color(VocabEntryModel.masteryColors[idx]);
          return InkWell(
            onTap: () async {
              await _store.updateMasteryLevel(entry.id, idx);
              _loadData();
            },
            child: Container(
              margin: EdgeInsets.symmetric(horizontal: 2),
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? color.withAlpha(40) : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                  color: isSelected ? color : context.borderSubtle,
                  width: isSelected ? 1.5 : 1,
                ),
              ),
              child: Text(
                '$idx',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : context.textTertiary,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }
}
