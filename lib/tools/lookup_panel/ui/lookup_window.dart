import 'package:audioplayers/audioplayers.dart';
import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../../../services/context_services_bridge.dart';
import '../../../services/note_capture_service.dart';
import '../../../components/markdown_view.dart';
import '../../../services/settings_store.dart';
import '../../../theme/app_theme.dart';
import '../../notebook/appflowy_codec.dart';
import '../../notebook/note_store.dart';
import '../../vocab_book/services/vocab_store.dart';
import '../services/dictionary_service.dart';
import '../services/lookup_coordinator.dart';

/// 查词浮窗独立应用
class LookupWindowApp extends StatelessWidget {
  const LookupWindowApp({
    super.key,
    required this.initialQuery,
    this.initialMode = LookupStartMode.dict,
  });

  final String initialQuery;

  /// 首屏走词典还是直接问 AI。见 [LookupStartMode]。
  final LookupStartMode initialMode;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: SettingsStore.instance.themeModeNotifier,
      builder: (context, currentThemeMode, _) {
        return MaterialApp(
          title: '查词 - V8 工作工具箱',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: currentThemeMode,
          home: Scaffold(
            // 查词浮窗整体透明：窗口本身由 macOS 原生层挖出圆角与投影，
            // 视觉边界由 LookupPanelView 内部容器绘制。
            // 此处不能改成 context.bg*，否则会盖掉窗口的透明通道，
            // 让圆角外沿出现一圈不透明的矩形毛边。
            backgroundColor: Colors.transparent,
            body: LookupPanelView(
            initialQuery: initialQuery,
            initialMode: initialMode,
            isSubWindow: true,
          ),
          ),
        );
      },
    );
  }
}

/// 查词浮窗控制器：负责打开与呼起独立浮窗
class LookupWindowLauncher {
  static const windowType = 'lookup:';

  /// 打开查词浮窗。
  ///
  /// [mode] 见 [LookupStartMode]：`dict` 走词典优先，`ai` 直接问 AI。缺省
  /// `dict` —— 既有调用方（右键查词、⌘D 热键）行为不变。
  static Future<void> open(String query, {LookupStartMode mode = LookupStartMode.dict}) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return;
    try {
      final windows = await WindowController.getAll();
      for (final win in windows) {
        if (win.arguments.startsWith(windowType)) {
          await win.hide();
        }
      }
      final controller = await WindowController.create(
        WindowConfiguration(
          // mode 也编进 arguments：子进程要从这里知道"直接问 AI"，
          // 而 WindowController.create 只有 arguments 一个传参通道。
          arguments: '$windowType${mode.name}:$cleanQuery',
          hiddenAtLaunch: false,
        ),
      );
      await controller.show();
      await ContextServicesBridge.instance.styleLookupWindow();
    } catch (e) {
      debugPrint('[LookupWindowLauncher] 打开浮窗失败: $e');
    }
  }
}

/// 查词模式。
///
/// 值名会跨进程写在子窗口 arguments 里，**改名等于改协议**——不要顺手改。
enum LookupStartMode {
  /// 词典优先（缺省）。
  dict,

  /// 跳过词典，直接 AI 分析。
  ai,
}

/// 解析查词模式。生产与测试都用（子窗口入口据它决定首屏走哪条路）。
///
/// 未知值一律回落 [LookupStartMode.dict]：深链是外部输入（浏览器可以拼出任意
/// 字符串），把它当错误拒绝会让用户在浏览器里点了没反应；当 dict 处理至少有
/// 词典结果可用。
LookupStartMode parseLookupStartMode(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'ai':
      return LookupStartMode.ai;
    case 'dict':
    default:
      return LookupStartMode.dict;
  }
}

/// 查词面板主体视图
class LookupPanelView extends StatefulWidget {
  const LookupPanelView({
    super.key,
    required this.initialQuery,
    this.isSubWindow = false,
    this.onClose,
    this.initialMode = LookupStartMode.dict,
  });

  final String initialQuery;
  final bool isSubWindow;
  final VoidCallback? onClose;
  final LookupStartMode initialMode;

  @override
  State<LookupPanelView> createState() => _LookupPanelViewState();
}

class _LookupPanelViewState extends State<LookupPanelView> with WindowListener {
  final TextEditingController _queryController = TextEditingController();
  final AudioPlayer _audioPlayer = AudioPlayer();

  LookupResult? _result;
  bool _isLoading = false;
  bool _isInVocabBook = false;

  @override
  void initState() {
    super.initState();
    if (widget.isSubWindow) {
      windowManager.addListener(this);
      _setupWindowStyle();
    }

    _queryController.text = widget.initialQuery;
    if (widget.initialQuery.trim().isNotEmpty) {
      // 按入口意图分派：从「问 AI 深度解析」进来的直接走 AI，其余走词典。
      // 走错分支的后果是用户被强迫看一次他没要的词典查询结果。
      switch (widget.initialMode) {
        case LookupStartMode.ai:
          _forceAi();
        case LookupStartMode.dict:
          _doLookup(widget.initialQuery.trim());
      }
    }
  }

  Future<void> _setupWindowStyle() async {
    try {
      // 尺寸由本窗口自己声明。原生侧（MainFlutterWindow）原来会把每个子窗口
      // 一律 setFrame(screen.visibleFrame) 铺满屏幕；那里现在只管样式，
      // 尺寸交给知道自己是哪种窗口的这一侧。420×520 是配置浮窗的老尺寸
      // （configureLookupWindow 一直用这个值）。
      await windowManager.setSize(const Size(420, 520), animate: false);
      await windowManager.setMinimumSize(const Size(360, 320));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setTitle('查词');
      await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
      await windowManager.setBackgroundColor(Colors.transparent);
      await windowManager.setHasShadow(true);
      await ContextServicesBridge.instance.styleLookupWindow();
    } catch (_) {}
  }

  @override
  void onWindowBlur() {
    // 失焦自动关闭
    if (widget.isSubWindow) {
      windowManager.close();
    }
  }

  @override
  void dispose() {
    if (widget.isSubWindow) {
      windowManager.removeListener(this);
    }
    _audioPlayer.dispose();
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _doLookup(String text) async {
    final q = text.trim();
    if (q.isEmpty) return;

    setState(() => _isLoading = true);

    // 检查是否已在生词本
    final exists = await VocabStore.instance.existsWord(q);

    final res = await LookupCoordinator.lookup(q);

    if (mounted) {
      setState(() {
        _result = res;
        _isLoading = false;
        _isInVocabBook = exists;
      });
    }
  }

  Future<void> _forceAi() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;
    setState(() => _isLoading = true);
    final res = await LookupCoordinator.forceAi(q);
    if (mounted) {
      setState(() {
        _result = res;
        _isLoading = false;
      });
    }
  }

  Future<void> _forceDictionary() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;
    setState(() => _isLoading = true);
    final res = await LookupCoordinator.forceDictionary(q);
    if (mounted) {
      setState(() {
        _result = res;
        _isLoading = false;
      });
    }
  }

  Future<void> _playAudio(String? url) async {
    if (url == null || url.isEmpty) return;
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(UrlSource(url));
    } catch (e) {
      debugPrint('[LookupPanel] Play audio error: $e');
    }
  }

  Future<void> _addToVocabBook() async {
    final res = _result;
    if (res == null) return;

    final dict = res.dictionaryResult;
    final word = res.query;

    await VocabStore.instance.insertFromDictionary(
      word: word,
      phonetic: dict?.phonetic,
      audioUrl: dict?.audioUrl,
      partOfSpeech: dict?.primaryPartOfSpeech,
      definitions: dict?.allDefinitions ?? [res.youdaoTranslation ?? res.aiTranslation ?? ''],
      examples: dict?.allExamples ?? const [],
      sourceContext: null,
    );

    if (mounted) {
      setState(() => _isInVocabBook = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已添加至生词本 📚'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _saveAsNote() async {
    final res = _result;
    if (res == null) return;

    final title = '查词：${res.query}';
    final sb = StringBuffer();

    if (res.dictionaryResult != null) {
      final dict = res.dictionaryResult!;
      if (dict.phonetic != null) sb.writeln('音标：${dict.phonetic}\n');
      for (final m in dict.meanings) {
        if (m.partOfSpeech.isNotEmpty) sb.writeln('### ${m.partOfSpeech}');
        for (final def in m.definitions) {
          sb.writeln('- $def');
        }
        for (final ex in m.examples) {
          sb.writeln('  > $ex');
        }
        sb.writeln();
      }
    }

    if (res.youdaoTranslation != null && res.youdaoTranslation!.isNotEmpty) {
      sb.writeln('### 中文释义');
      sb.writeln(res.youdaoTranslation);
      sb.writeln();
    }

    if (res.aiTranslation != null && res.aiTranslation!.isNotEmpty) {
      sb.writeln('### AI 解析');
      sb.writeln(res.aiTranslation);
    }

    final fullText = sb.toString().trim();

    final defaultNb = await NoteStore.instance.defaultCaptureNotebook();
    final defaultId = defaultNb?.id ??
        (await NoteCaptureService.instance.getDefaultNotebookId()) ??
        (await NoteStore.instance.allNotebooks()).firstOrNull?.id;

    if (defaultId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在笔记工具中创建笔记本')),
        );
      }
      return;
    }

    // 转为 AppFlowy delta json
    final doc = AppFlowyCodec.parseToDocument(fullText);
    final deltaJson = AppFlowyCodec.documentToJson(doc);

    await NoteStore.instance.createNote(
      title: title,
      deltaJson: deltaJson,
      notebookId: defaultId,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已保存为笔记 📝'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _close() {
    if (widget.isSubWindow) {
      windowManager.close();
    } else {
      widget.onClose?.call();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgCard = isDark ? context.bgCard : AppTheme.lightBgCard;
    final bgSidebar = isDark ? context.bgSidebar : AppTheme.lightBgSidebar;
    final bgInput = isDark ? context.bgInput : AppTheme.lightBgInput;
    final borderSubtle = isDark ? context.borderSubtle : AppTheme.lightBorderSubtle;
    final borderStrong = isDark ? context.borderStrong : AppTheme.lightBorderStrong;
    final textPrimary = isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary = isDark ? context.textSecondary : AppTheme.lightTextSecondary;
    final textTertiary = isDark ? context.textTertiary : AppTheme.lightTextTertiary;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
          _close();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Container(
        margin: widget.isSubWindow ? const EdgeInsets.all(4) : EdgeInsets.zero,
        decoration: BoxDecoration(
          color: bgCard,
          border: Border.all(color: borderStrong, width: 1.2),
          borderRadius: BorderRadius.circular(widget.isSubWindow ? 12 : 8),
          boxShadow: [
            BoxShadow(
              color: isDark ? Colors.black.withValues(alpha: 0.35) : Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // 顶部搜索与控制栏
            _buildHeader(
              bgSidebar: bgSidebar,
              textPrimary: textPrimary,
              textTertiary: textTertiary,
            ),
            Divider(height: 1, color: borderSubtle),

            // 主体内容展示
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildContent(
                      isDark: isDark,
                      bgInput: bgInput,
                      borderSubtle: borderSubtle,
                      textPrimary: textPrimary,
                      textSecondary: textSecondary,
                      textTertiary: textTertiary,
                    ),
            ),

            // 底部操作栏
            Divider(height: 1, color: borderSubtle),
            _buildBottomBar(bgSidebar: bgSidebar),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader({
    required Color bgSidebar,
    required Color textPrimary,
    required Color textTertiary,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: bgSidebar,
        borderRadius: BorderRadius.vertical(top: Radius.circular(widget.isSubWindow ? 12 : 8)),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 18, color: context.accentText),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _queryController,
              autofocus: true,
              style: TextStyle(fontSize: 14, color: textPrimary),
              decoration: InputDecoration(
                hintText: '输入单词、短语或长句…',
                hintStyle: TextStyle(fontSize: 13, color: textTertiary),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: _doLookup,
            ),
          ),
          if (_queryController.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.cancel_rounded, size: 16, color: textTertiary),
              padding: EdgeInsets.zero,
              tooltip: '清空输入',
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              onPressed: () {
                _queryController.clear();
                setState(() => _result = null);
              },
            ),
          const SizedBox(width: 4),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 16, color: textTertiary),
            padding: EdgeInsets.zero,
            tooltip: '关闭 (Esc)',
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            onPressed: _close,
          ),
        ],
      ),
    );
  }

  Widget _buildContent({
    required bool isDark,
    required Color bgInput,
    required Color borderSubtle,
    required Color textPrimary,
    required Color textSecondary,
    required Color textTertiary,
  }) {
    final res = _result;
    if (res == null) {
      return Center(
        child: Text(
          '在输入框中输入词汇按回车查询\n或在任意应用中按 ⌥D 快捷查词',
          textAlign: TextAlign.center,
          style: TextStyle(color: textTertiary, fontSize: 13, height: 1.6),
        ),
      );
    }

    if (res.error != null && res.dictionaryResult == null && res.aiTranslation == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, color: textTertiary, size: 40),
              const SizedBox(height: 10),
              Text(
                res.error ?? '词典中未收录此词',
                style: TextStyle(color: textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _forceAi,
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('使用 AI 深度解析'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 单词头部
          if (res.dictionaryResult != null)
            _buildWordHeader(
              res.dictionaryResult!,
              textPrimary: textPrimary,
              textSecondary: textSecondary,
            ),

          // 中文释义快速看
          if (res.youdaoTranslation != null && res.youdaoTranslation!.isNotEmpty) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: bgInput,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderSubtle),
              ),
              child: Text(
                '中文：${res.youdaoTranslation!}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textPrimary),
              ),
            ),
          ],

          // 词典释义列表
          if (res.dictionaryResult != null) ...[
            for (final m in res.dictionaryResult!.meanings) ...[
              if (m.partOfSpeech.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: context.accentSubtle,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          m.partOfSpeech,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: context.accentText,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final def in m.definitions)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('• ', style: TextStyle(color: context.accentText)),
                      Expanded(
                        child: Text(
                          def,
                          style: TextStyle(fontSize: 13, color: textPrimary, height: 1.4),
                        ),
                      ),
                    ],
                  ),
                ),
              for (final ex in m.examples)
                Container(
                  margin: const EdgeInsets.only(top: 4, bottom: 6, left: 10),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: bgInput,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ex,
                    style: TextStyle(fontSize: 12, color: textSecondary, fontStyle: FontStyle.italic),
                  ),
                ),
            ],
          ],

          // 词典结果下的 AI 深度解析建议按钮（未展开 AI 时）
          if (res.aiTranslation == null && res.dictionaryResult != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Center(
                child: TextButton.icon(
                  onPressed: _forceAi,
                  icon: Icon(Icons.auto_awesome, size: 14, color: context.accentText),
                  label: Text('使用 AI 深度解析（语境分析与用法拓展）', style: TextStyle(fontSize: 12, color: context.accentText)),
                ),
              ),
            ),

          // AI 翻译/解析区
          if (res.aiTranslation != null && res.aiTranslation!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: bgInput,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: context.accentSolid.withAlpha(50)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.auto_awesome, size: 14, color: context.accentText),
                      SizedBox(width: 6),
                      Text(
                        'AI 深度解析',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: context.accentText),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // 用共享的 Markdown 渲染，不是 Text：AI 返回的是 Markdown，
                  // 用 Text 会把 `**`、`##`、`- ` 这些源码裸呈给用户。
                  // AppMarkdownView 已是 AI 助手/资讯快报/磁盘报告/笔记问答
                  // 四处的标准组件，唯独查词浮窗漏了它。
                  AppMarkdownView(
                    data: res.aiTranslation!,
                    baseStyle: TextStyle(fontSize: 13, color: textPrimary, height: 1.5),
                    // 默认 selectable —— AI 文本要能选中复制。
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWordHeader(
    DictionaryResult dict, {
    required Color textPrimary,
    required Color textSecondary,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            dict.word,
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textPrimary),
          ),
          if (dict.phonetic != null && dict.phonetic!.isNotEmpty) ...[
            SizedBox(width: 8),
            Text(
              dict.phonetic!,
              style: TextStyle(fontSize: 14, color: textSecondary),
            ),
          ],
          SizedBox(width: 6),
          IconButton(
            icon: Icon(
              Icons.volume_up_rounded,
              size: 20,
              color: dict.audioUrl != null ? context.accentText : context.textDisabled,
            ),
            tooltip: dict.audioUrl != null ? '发音' : '无发音音频',
            onPressed: dict.audioUrl != null ? () => _playAudio(dict.audioUrl) : null,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar({required Color bgSidebar}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: bgSidebar,
      child: Row(
        children: [
          // 添加生词本
          FilledButton.tonalIcon(
            onPressed: _isInVocabBook ? null : _addToVocabBook,
            icon: Icon(
              _isInVocabBook ? Icons.check_circle_outline : Icons.bookmark_add_outlined,
              size: 15,
            ),
            label: Text(_isInVocabBook ? '已在生词本' : '加生词本', style: const TextStyle(fontSize: 12)),
          ),
          const SizedBox(width: 8),

          // 模式切换按钮：根据当前模式切换
          if (_result?.mode == LookupMode.aiTranslation)
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _forceDictionary,
              icon: const Icon(Icons.menu_book_outlined, size: 14),
              label: const Text('查词典', style: TextStyle(fontSize: 12)),
            )
          else
            OutlinedButton.icon(
              onPressed: _isLoading ? null : _forceAi,
              icon: const Icon(Icons.auto_awesome, size: 14),
              label: const Text('问 AI', style: TextStyle(fontSize: 12)),
            ),
          const Spacer(),

          // 存为笔记
          FilledButton.icon(
            onPressed: _result == null ? null : _saveAsNote,
            icon: const Icon(Icons.note_add_outlined, size: 15),
            label: const Text('存为笔记', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
