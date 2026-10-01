import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:appflowy_editor/appflowy_editor.dart';

import '../../../theme/app_theme.dart';
import '../appflowy_codec.dart';
import '../note_database.dart';
import '../note_store.dart';
import '../services/clipboard_image_service.dart';
import 'asset_fields_panel.dart';
import 'related_notes_section.dart';
import 'components/attachment_block_component.dart';
import 'components/note_code_block_component.dart';
import 'components/note_editor_toolbar.dart';
import 'components/note_image_block_component.dart';
import 'components/note_image_menu.dart';
import 'components/note_mindmap_component.dart';
import 'notebook_light_scope.dart';

/// 粘贴图片的三种结局。分开是因为它们要的反馈不同：handled 已插入、
/// failed 认出了但出错（已提示用户）、notAnImage 剪贴板里没有图片形态，
/// 调用方应继续按文本粘贴。
enum _PasteOutcome { handled, failed, notAnImage }

/// 接管 ⌘V 之后的纯文本粘贴核心：选中区删除 → 属性继承 → URL/电话识别 →
/// 按行拆段 → 单/多行插入。
///
/// 关于本条要求的证据边界，说清楚：契约是从接管前包内实现
/// （`appflowy_editor` 的 `paste_command.dart`）读出来的，**不是跑出来的**——
/// 那个 handler 是包内私有的，测试与生产都调不到它。所以这里的单测证明的是
/// 「接管后符合这份读源码得出的契约」，不能宣称「与接管前的行为逐位相等」。
/// 后者只能由实机对比确认（tasks 5.5）。
@visibleForTesting
Future<void> insertPlainTextPaste(EditorState state, String text) async {
  final attributes = state.getDeltaAttributesInSelectionStart();
  final selection = await state.deleteSelectionIfNeeded();
  if (selection == null) return;

  // 这里**没有** URL / 电话转链接的分支，是刻意的。
  //
  // 接管前包内 `pastePlainText` 确实调了 `maybeConvertToUrlOrPhone`，但那个
  // 分支不可达：它排在 `deleteSelectionIfNeeded()` 之后，而后者删掉选中内容后
  // 返回的 selection 必然 isCollapsed；`maybeConvertToUrlOrPhone` 的守卫
  // 又要求 `isCollapsed == false`，于是永远 return false。粘贴一个 URL 进去，
  // 接管前从来是当纯文本插入，不会变成链接。
  //
  // 照抄一遍这条死分支非但拿不到"粘 URL 变链接"的好处（formatText 落在已被
  // 删空的 delta 上，插入结果是空），还平白改变行为。所以这里只做文本分支。
  final nodes = text
      .split('\n')
      .map((line) => line.replaceAll('\r', '').trimRight())
      .map((line) => paragraphNode(
            delta: Delta()..insert(line, attributes: attributes ?? {}),
          ))
      .toList();

  if (nodes.isEmpty) return;
  if (nodes.length == 1) {
    await state.pasteSingleLineNode(nodes.first);
  } else {
    await state.pasteMultiLineNodes(nodes);
  }
}

class NoteEditor extends StatefulWidget {
  final Note? note;
  final VoidCallback? onSaved;
  final VoidCallback? onTogglePin;
  final VoidCallback? onDelete;
  final VoidCallback? onRestore;
  final VoidCallback? onPermanentDelete;

  /// 点击关联笔记时跳转（阶段三）。
  final void Function(String noteId)? onOpenNote;

  /// 编辑器从数据库重新读到当前笔记时回调（资产/关联写入后的快照刷新）。
  ///
  /// 父层用它替换自己持有的 `note` 快照，使元数据栏的资产 chip 与关联计数反映
  /// 持久化现状，而不是打开编辑器时的旧值。
  final void Function(Note note)? onNoteReloaded;

  const NoteEditor({
    super.key,
    this.note,
    this.onSaved,
    this.onTogglePin,
    this.onDelete,
    this.onRestore,
    this.onPermanentDelete,
    this.onOpenNote,
    this.onNoteReloaded,
  });

  @override
  State<NoteEditor> createState() => NoteEditorState();
}

class NoteEditorState extends State<NoteEditor> {
  EditorState? _editorState;
  EditorScrollController? _editorScrollController;
  StreamSubscription? _transactionSub;
  late TextEditingController _titleCtrl;
  Timer? _bodyDebounce;
  bool _isSaving = false;

  /// 追加 Markdown 内容到当前活跃编辑器末尾，并实时更新视图与持久化到数据库。
  Future<bool> appendMarkdown(String markdown) async {
    if (_editorState == null || !mounted) return false;
    try {
      final appendDoc = AppFlowyCodec.parseToDocument('\n\n---\n\n$markdown');
      final transaction = _editorState!.transaction;
      var insertIdx = _editorState!.document.root.children.length;
      for (final node in appendDoc.root.children) {
        transaction.insertNode([insertIdx++], node);
      }
      await _editorState!.apply(transaction);

      // 光标置底并激活焦点（自动触发将新段落滚动进入视野）
      _focusEditorAtEnd();

      // 立即保存至底层存储并通知刷新
      await _save();
      return true;
    } catch (e) {
      debugPrint('NoteEditor.appendMarkdown 出错: $e');
      return false;
    }
  }

  /// 获取当前编辑器的文档模型实例
  Document? get document => _editorState?.document;

  /// 获取当前编辑器的纯文本内容
  String get plainText =>
      _editorState == null ? '' : AppFlowyCodec.documentToPlainText(_editorState!.document);

  List<Notebook> _notebooks = [];
  List<Tag> _allTags = [];
  List<Tag> _noteTags = [];

  /// 当前笔记的关联数，用于元数据栏的「关联 N」chip（0 时不渲染）。
  int _relatedCount = 0;

  late FocusNode _editorFocusNode;
  late final Map<String, BlockComponentBuilder> _blockComponentBuilders;

  EditorStyle get _editorStyle => EditorStyle.desktop(
    padding: EdgeInsets.symmetric(horizontal: 36, vertical: 20),
    cursorColor: context.accentSolid,
    selectionColor: context.accentSolid.withValues(alpha: 0.2),
    textStyleConfiguration: const TextStyleConfiguration(
      text: TextStyle(fontSize: 15.0, color: Color(0xFF0F172A), height: 1.6),
      bold: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
      italic: TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF0F172A)),
    ),
  );

  @override
  void initState() {
    super.initState();
    _editorFocusNode = FocusNode(debugLabel: 'NoteEditorCanvasFocus');
    _titleCtrl = TextEditingController(text: widget.note?.title ?? '');
    _initBlockBuilders();
    _initEditor();
    _loadMetadata();
  }

  void _initBlockBuilders() {
    // 注意：此处不读 context.*——_initBlockBuilders 由 initState 调用，
    // 而 initState 期间禁止 dependOnInheritedWidget（读 ThemeExtension 会触发）。
    // 表格描边需要强调色的地方改在 build 内解析后传入。
    _blockComponentBuilders = {
      ...standardBlockComponentBuilderMap,
      TableBlockKeys.type: TableBlockComponentBuilder(
        tableStyle: TableStyle(
          borderWidth: 1.0,
          borderColor: Color(0xFFE2E8F0),
        ),
      ),
      TableCellBlockKeys.type: TableCellBlockComponentBuilder(
        colorBuilder: (context, node) {
          final row =
              node.attributes[TableCellBlockKeys.rowPosition] as int? ?? 0;
          if (row == 0) {
            return const Color(0xFFF8FAFC);
          }
          return Colors.white;
        },
      ),
      // 用我们自己的图片块，而不是包内的 ImageBlockComponentBuilder：后者
      // 内部的 ResizableImage 把 width 抄进 State 只抄一次，导致点预设百分比
      // 屏幕不变（详见 note_image_block_component.dart 顶部说明）。
      ImageBlockKeys.type: NoteImageBlockComponentBuilder(
        showMenu: true,
        menuBuilder: (node, state) => buildNoteImageMenu(context, node, state),
      ),
      NoteCodeBlockKeys.type: NoteCodeBlockComponentBuilder(),
      'code': NoteCodeBlockComponentBuilder(),
      AttachmentBlockKeys.type: AttachmentBlockComponentBuilder(),
      MindMapBlockKeys.type: MindMapBlockComponentBuilder(),
    };
  }

  void _initEditor() {
    _transactionSub?.cancel();
    _editorScrollController?.dispose();
    if (widget.note != null) {
      final doc = AppFlowyCodec.parseToDocument(widget.note!.deltaJson);
      _editorState = EditorState(document: doc);
      _editorScrollController = EditorScrollController(
        editorState: _editorState!,
        shrinkWrap: false,
      );
      _transactionSub = _editorState!.transactionStream.listen((_) {
        _scheduleBodySave();
      });
    } else {
      _editorState = null;
      _editorScrollController = null;
    }
  }

  @override
  void didUpdateWidget(NoteEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note?.id != widget.note?.id) {
      _titleCtrl.text = widget.note?.title ?? '';
      _initEditor();
      _loadMetadata();
    }
  }

  @override
  void dispose() {
    _transactionSub?.cancel();
    _bodyDebounce?.cancel();
    _editorScrollController?.dispose();
    _editorState?.dispose();
    _editorFocusNode.dispose();
    _titleCtrl.dispose();
    super.dispose();
  }

  void _focusEditorAtEnd() {
    if (_editorState == null || !mounted) return;
    _editorFocusNode.requestFocus();
    if (_editorState!.document.root.children.isNotEmpty) {
      final lastNode = _editorState!.document.root.children.last;
      final length = lastNode.delta?.length ?? 0;
      _editorState!.updateSelectionWithReason(
        Selection.single(path: lastNode.path, startOffset: length),
        reason: SelectionUpdateReason.uiEvent,
      );
    }
  }

  Future<void> _loadMetadata() async {
    if (widget.note == null) return;
    try {
      final store = NoteStore.instance;
      final nbs = await store.allNotebooks();
      final tags = await store.allTags();
      final noteTags = await store.tagsForNote(widget.note!.id);
      final related = await store.relatedNotes(widget.note!.id);
      if (mounted) {
        setState(() {
          _notebooks = nbs;
          _allTags = tags;
          _noteTags = noteTags;
          _relatedCount = related.length;
        });
      }
    } catch (e) {
      debugPrint('NoteEditor._loadMetadata safe notice: $e');
    }
  }

  /// 弹窗（资产 / 整理 / 关联）写入后刷新元数据栏与外部列表。
  ///
  /// 除元数据外还重新读一次当前笔记本身：资产 chip 的文案（品类 / 到期倒计时）
  /// 与关联计数都来自 `widget.note`，只重读列表的话这些值会停留在打开时的快照，
  /// 表现为「保存后内容丢失」。
  Future<void> _refreshMetadata() async {
    await _loadMetadata();
    final reloaded = await _reloadNote();
    widget.onSaved?.call();
    return reloaded;
  }

  /// 从数据库重新读取当前笔记，并上报给父层替换其快照。
  ///
  /// 父层的 `_refresh` 只在笔记仍处于当前过滤列表内时才更新 `_selectedNote`；
  /// 一旦过滤条件变化（搜索词、标签、笔记本切换）它会改为清空选择，资产 chip
  /// 就再也拿不到新值。这里显式回传，保证写入后 UI 反映数据库现状。
  Future<void> _reloadNote() async {
    final id = widget.note?.id;
    if (id == null) return;
    try {
      final latest = await NoteStore.instance.noteById(id);
      if (latest != null && mounted) {
        widget.onNoteReloaded?.call(latest);
      }
    } catch (e) {
      debugPrint('NoteEditor._reloadNote safe notice: $e');
    }
  }

  Future<void> _openAssetDialog() async {
    final note = widget.note;
    if (note == null) return;
    await showAssetDialog(context, note: note, onChanged: _refreshMetadata);
    // 弹窗可能在父组件重建后仍持有旧 note 引用，取最新一份再刷新。
    await _refreshMetadata();
  }

  Future<void> _openRelatedDialog() async {
    final note = widget.note;
    if (note == null) return;
    await showRelatedNotesDialog(
      context,
      note: note,
      onOpenNote: (id) => widget.onOpenNote?.call(id),
      onChanged: _refreshMetadata,
    );
    await _refreshMetadata();
  }

  void _onTitleChanged(String _) {
    _scheduleBodySave();
  }

  void _scheduleBodySave() {
    _bodyDebounce?.cancel();
    _bodyDebounce = Timer(const Duration(milliseconds: 800), _save);
  }

  Future<void> _save() async {
    if (_isSaving || widget.note == null || _editorState == null) return;
    _isSaving = true;
    if (mounted) setState(() {});

    try {
      final contentJson = AppFlowyCodec.documentToJson(_editorState!.document);
      final currentTitle = _titleCtrl.text.trim();
      await NoteStore.instance.updateNote(
        id: widget.note!.id,
        title: currentTitle.isEmpty ? '无标题笔记' : currentTitle,
        deltaJson: contentJson,
      );
      widget.onSaved?.call();
    } catch (e) {
      debugPrint('Auto-save error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Notebook & Tag operations
  // ---------------------------------------------------------------------------

  Future<void> _changeNotebook(String? newNotebookId) async {
    if (widget.note == null) return;
    await NoteStore.instance.updateNote(
      id: widget.note!.id,
      notebookId: newNotebookId,
    );
    await _loadMetadata();
    widget.onSaved?.call();
  }

  Future<void> _togglePin() async {
    if (widget.note == null) return;
    final newPinned = !widget.note!.isPinned;
    await NoteStore.instance.updateNote(
      id: widget.note!.id,
      isPinned: newPinned,
    );
    widget.onTogglePin?.call();
    widget.onSaved?.call();
  }

  Future<void> _addTagDialog() async {
    if (widget.note == null) return;
    final tagCtrl = TextEditingController();

    final selected = await showDialog<String>(
      context: context,
      builder: (ctx) => NotebookLightScope(
        child: AlertDialog(
          backgroundColor: context.bgCard,
          title: const Text('添加标签', style: AppTheme.fontTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: tagCtrl,
                decoration: const InputDecoration(
                  hintText: '输入新标签名称或选择已有标签',
                  isDense: true,
                ),
                autofocus: true,
              ),
              if (_allTags.isNotEmpty) ...[
                const SizedBox(height: AppTheme.space12),
                const Text('已有标签：', style: AppTheme.fontCaption),
                const SizedBox(height: AppTheme.space8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _allTags
                      .where((t) => !_noteTags.any((nt) => nt.id == t.id))
                      .map((t) {
                        return ActionChip(
                          label: Text(t.name),
                          onPressed: () => Navigator.pop(ctx, t.name),
                        );
                      })
                      .toList(),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, tagCtrl.text.trim()),
              child: const Text('添加'),
            ),
          ],
        ),
      ),
    );

    if (selected != null && selected.isNotEmpty) {
      final store = NoteStore.instance;
      final match = _allTags.where((t) => t.name == selected).toList();
      String tagId;
      if (match.isNotEmpty) {
        tagId = match.first.id;
      } else {
        tagId = await store.createTag(selected);
      }
      final newTagIds = {..._noteTags.map((t) => t.id), tagId}.toList();
      await store.setNoteTags(widget.note!.id, newTagIds);
      await _loadMetadata();
      widget.onSaved?.call();
    }
  }

  Future<void> _removeTag(String tagId) async {
    if (widget.note == null) return;
    final newTagIds = _noteTags
        .map((t) => t.id)
        .where((id) => id != tagId)
        .toList();
    await NoteStore.instance.setNoteTags(widget.note!.id, newTagIds);
    await _loadMetadata();
    widget.onSaved?.call();
  }

  // ---------------------------------------------------------------------------
  // 粘贴（图片优先，回落纯文本）
  //
  // 为什么在这里接管：AppFlowyEditor 的键盘服务把 Focus(onKeyEvent:) 挂在它
  // 自己的 focusNode 上，比外层 Shortcuts 更早被问到，命中 ⌘V 后返回 handled
  // 即终止分发。包自带的 pasteCommand 只读 kTextPlain，剪贴板里只有图片没有
  // 文本时它什么都不做却返回 handled——按键被吃掉，外层的 CallbackShortcuts
  // 永远收不到。所以必须从命令表这一层接管，而不是在外层抢按键。
  // ---------------------------------------------------------------------------

  /// 接管 ⌘V / ⌃V 后的统一入口：先试图片，拿不到再按纯文本粘贴。
  ///
  /// [state] 由编辑器传入（当前获得焦点的那个 EditorState），不用
  /// [_editorState] 字段——两者绝大多数时候相同，但依赖字段意味着将来
  /// 多编辑器时会静默插错地方。
  Future<void> _handlePaste(EditorState state) async {
    if (widget.note == null) return;

    final outcome = await _pasteClipboardImage(widget.note!.id, state);
    if (outcome != _PasteOutcome.notAnImage) return;

    await _pastePlainText(state);
  }

  /// 尝试把剪贴板里的图片存进笔记并在光标处插入图片块。
  ///
  /// 返回值区分三件事，因为它们要的反馈不同：
  ///   handled    —— 图片已插入；
  ///   failed     —— 认出了图片但中途出错（已弹 snackbar）；
  ///   notAnImage —— 剪贴板里没有图片形态，调用方应继续按文本粘贴。
  Future<_PasteOutcome> _pasteClipboardImage(
    String noteId,
    EditorState state,
  ) async {
    final result = await ClipboardImageService.instance.readImage();
    final image = result.asSuccess();
    if (image == null) {
      final failure = result.asFailure();
      // 只有"真的尝试过但没成功"才需要打扰用户。剪贴板里压根没有图片形态
      // 是正常情况（用户可能就是想粘一段文字），交给文本分支处理即可。
      if (failure != null &&
          failure.$1 != ClipboardImageFailure.nothingPasteable) {
        _showPasteError(_describeImageFailure(failure.$1, failure.$2));
      }
      return _PasteOutcome.failed;
    }

    try {
      final savedPath = await NoteStore.instance.saveAttachment(
        noteId: noteId,
        sourceFile: image.file,
        filename: 'paste_${DateTime.now().millisecondsSinceEpoch}'
            '${p.extension(image.file.path)}',
      );
      _insertImageAtCursor(state, savedPath);
      return _PasteOutcome.handled;
    } catch (e) {
      debugPrint('[NoteEditor] 保存粘贴图片失败: $e');
      _showPasteError('图片保存失败：$e');
      return _PasteOutcome.failed;
    } finally {
      // 只删服务自己生成的临时文件；用户磁盘上的原件删了会毁数据。
      if (image.ownedByService) {
        try {
          if (await image.file.exists()) await image.file.delete();
        } catch (_) {}
      }
    }
  }

  /// 接管后的纯文本粘贴。
  ///
  /// 逐条对齐接管前（appflowy_editor 内部）的行为：选中区先删除、继承选中
  /// 处的行内属性、URL 与电话识别并写成 href、按行拆段、单/多行走对应插入
  /// 路径。漏一条，用户就会觉得"粘贴变了"——那比原来的 bug 更烦，因为它
  /// 影响每一次粘贴而不是只影响图片。
  Future<void> _pastePlainText(EditorState state) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    await insertPlainTextPaste(state, text);
  }

  /// 把取图失败翻译成用户能据此行动的一句话。
  ///
  /// 每类说清是哪一步坏的，不共用一句「操作失败」——「没识别到图片」和
  /// 「下载失败」的下一步完全不同。这次的 bug 能藏住，静默失败是主因。
  static String _describeImageFailure(
    ClipboardImageFailure reason,
    String? detail,
  ) {
    final suffix = (detail != null && detail.isNotEmpty) ? '（$detail）' : '';
    return switch (reason) {
      ClipboardImageFailure.nothingPasteable => '剪贴板中没有可识别的图片',
      ClipboardImageFailure.bitmapReadFailed =>
        '读取剪贴板图片失败，可能需要在系统设置里授予自动化权限',
      ClipboardImageFailure.downloadFailed => '图片下载失败$suffix',
      ClipboardImageFailure.tooLarge =>
        '图片超过 $suffix大小上限，已取消粘贴',
    };
  }

  void _showPasteError(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: context.errorSolid,
      ),
    );
  }

  /// 接管后装配给编辑器的命令表。
  ///
  /// 只替换两条粘贴命令，其余（copy / cut / undo / redo / 方向键 / markdown
  /// 触发…）保持包的默认集合。按身份 `!=` 过滤而不是按下标：包升级时若
  /// pasteCommand 不存在，这里是编译错误而不是静默的行为改变。
  List<CommandShortcutEvent> _buildCommandShortcutEvents() {
    return [
      ...standardCommandShortcutEvents.where(
        (e) => e != pasteCommand && e != pasteTextWithoutFormattingCommand,
      ),
      CommandShortcutEvent(
        key: 'v8 custom paste',
        command: 'ctrl+v',
        macOSCommand: 'cmd+v',
        getDescription: () => 'V8 粘贴（图片优先）',
        handler: (state) {
          _handlePaste(state);
          return KeyEventResult.handled;
        },
      ),
    ];
  }

  void _insertImageAtCursor(EditorState state, String path) {
    final selection = state.selection;
    final targetPath = selection != null
        ? [selection.end.path[0] + 1]
        : [state.document.root.children.length];

    final node = imageNode(url: path);
    final transaction = state.transaction..insertNode(targetPath, node);
    state.apply(transaction);
    _scheduleBodySave();
  }

  Future<String> _saveAttachment(File file, String filename) async {
    return await NoteStore.instance.saveAttachment(
      noteId: widget.note!.id,
      sourceFile: file,
      filename: filename,
    );
  }

  /// 添加附件：保存到笔记附件目录并返回引用信息供工具栏插入附件块。
  ///
  /// 只回传附件 ID 与展示元数据——文件路径由附件块渲染时查表解析，
  /// 确保引用的是应用副本而非用户选择的原始文件。
  Future<List<AttachmentRef>> _addAttachments(List<File> files) async {
    final refs = <AttachmentRef>[];
    for (final file in files) {
      try {
        final attId = await NoteStore.instance.addAttachment(
          noteId: widget.note!.id,
          sourceFile: file,
        );
        final stat = await file.stat();
        refs.add(
          AttachmentRef(
            attachmentId: attId,
            filename: p.basename(file.path),
            sizeBytes: stat.size,
          ),
        );
      } catch (e) {
        debugPrint('添加附件失败 ${file.path}: $e');
      }
    }
    _scheduleBodySave();
    return refs;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    if (widget.note == null || _editorState == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.note_alt_outlined,
              size: 64,
              color: context.textTertiary,
            ),
            SizedBox(height: AppTheme.space16),
            Text(
              '选择或创建一条笔记开始记录',
              style: AppTheme.fontBody.copyWith(color: context.textTertiary),
            ),
          ],
        ),
      );
    }

    final currentNotebook = _notebooks
        .where((nb) => nb.id == widget.note!.notebookId)
        .firstOrNull;

    // 这里曾经用 CallbackShortcuts 绑 ⌘V，但外层的 Shortcuts 结构性轮不到——
    // AppFlowyEditor 的 Focus(onKeyEvent:) 挂在焦点节点上更早接到并返回
    // handled。粘贴命令现在从编辑器的命令表接管，见 _buildCommandShortcutEvents。
    return NotebookLightScope(
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 废纸篓警告横幅
            if (widget.note!.isDeleted)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppTheme.space16,
                  vertical: AppTheme.space8,
                ),
                color: context.warningText.withValues(alpha: 0x1F / 255),
                child: Row(
                  children: [
                    Icon(
                      Icons.delete_outline,
                      size: 18,
                      color: context.warningText,
                    ),
                    SizedBox(width: AppTheme.space8),
                    Text(
                      '此笔记位于废纸篓中',
                      style: AppTheme.fontBody.copyWith(
                        color: context.warningText,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: widget.onRestore,
                      child: const Text('恢复笔记'),
                    ),
                    SizedBox(width: AppTheme.space8),
                    TextButton(
                      onPressed: widget.onPermanentDelete,
                      child: Text(
                        '彻底粉碎',
                        style: TextStyle(color: context.errorText),
                      ),
                    ),
                  ],
                ),
              ),

            // 元数据栏：笔记本选择器、标签列表、置顶切换
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.space16,
                vertical: 6,
              ),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  // 笔记本下拉选择
                  PopupMenuButton<String?>(
                    tooltip: '切换所属笔记本',
                    onSelected: (nbId) => _changeNotebook(nbId),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            currentNotebook?.icon ?? '📓',
                            style: const TextStyle(fontSize: 13),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            currentNotebook?.name ?? '默认笔记本',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF1E293B),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Icon(
                            Icons.arrow_drop_down,
                            size: 16,
                            color: Color(0xFF64748B),
                          ),
                        ],
                      ),
                    ),
                    itemBuilder: (ctx) => [
                      const PopupMenuItem<String?>(
                        value: null,
                        child: Text('📓 默认笔记本 (未归类)'),
                      ),
                      ..._notebooks.map(
                        (nb) => PopupMenuItem<String?>(
                          value: nb.id,
                          child: Text('${nb.icon} ${nb.name}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppTheme.space8),

                  // 标签列表
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ..._noteTags.map(
                            (tag) => Container(
                              margin: const EdgeInsets.only(right: 6),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: const Color(0xFFE2E8F0),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '#${tag.name}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Color(0xFF475569),
                                    ),
                                  ),
                                  const SizedBox(width: 2),
                                  InkWell(
                                    onTap: () => _removeTag(tag.id),
                                    child: const Icon(
                                      Icons.close,
                                      size: 12,
                                      color: Color(0xFF94A3B8),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          InkWell(
                            onTap: _addTagDialog,
                            borderRadius: BorderRadius.circular(4),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.add,
                                    size: 12,
                                    color: context.accentText,
                                  ),
                                  Text(
                                    ' 标签',
                                    style: TextStyle(
                                      color: context.accentText,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // 资产 / 凭证入口：有数据显示品类或到期倒计时
                          AssetChipButton(
                            note: widget.note!,
                            onTap: _openAssetDialog,
                          ),

                          // AI 整理建议入口
                          AiTidyChip(
                            note: widget.note!,
                            onChanged: _refreshMetadata,
                          ),

                          // 关联笔记入口：无关联时不渲染
                          if (_relatedCount > 0)
                            MetaChip(
                              icon: Icons.hub_outlined,
                              label: '关联 $_relatedCount',
                              tooltip: '查看 / 移除关联笔记',
                              onTap: _openRelatedDialog,
                            ),
                        ],
                      ),
                    ),
                  ),

                  // 置顶按钮
                  IconButton(
                    icon: Icon(
                      widget.note!.isPinned
                          ? Icons.push_pin
                          : Icons.push_pin_outlined,
                      size: 18,
                      color: widget.note!.isPinned
                          ? context.accentSolid
                          : context.textTertiary,
                    ),
                    tooltip: widget.note!.isPinned ? '取消置顶' : '置顶笔记',
                    onPressed: _togglePin,
                  ),
                ],
              ),
            ),

            // 笔记标题输入框
            Container(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.space24,
                AppTheme.space12,
                AppTheme.space24,
                AppTheme.space4,
              ),
              color: Colors.white,
              child: TextField(
                controller: _titleCtrl,
                onChanged: _onTitleChanged,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  height: 1.3,
                ),
                decoration: const InputDecoration(
                  hintText: '笔记标题...',
                  hintStyle: TextStyle(
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.normal,
                  ),
                  border: InputBorder.none,
                  filled: false,
                  fillColor: Colors.transparent,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),

            // 编辑器格式工具栏（紧邻画布，属性入口已收拢进元数据栏）
            NoteEditorToolbar(
              editorState: _editorState!,
              onSaveAttachment: _saveAttachment,
              onAddAttachments: _addAttachments,
              // 与 ⌘V 同一条链路：读剪贴板 → 存附件 → 插图片块。
              onPasteImage: _editorState == null
                  ? null
                  : () => _handlePaste(_editorState!),
            ),

            // AppFlowyEditor 编辑器画布（由 AppFlowy 原生接管视口与滚动）
            Expanded(
              child: Container(
                color: Colors.white,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _focusEditorAtEnd,
                  child: AppFlowyEditor(
                    editorState: _editorState!,
                    editorScrollController: _editorScrollController,
                    editorStyle: _editorStyle,
                    blockComponentBuilders: _blockComponentBuilders,
                    // 接管粘贴命令：包默认的 pasteCommand 只读纯文本，剪贴板里
                    // 只有图片时它返回 handled 却什么都不做，⌘V 就被吞了。
                    commandShortcutEvents: _buildCommandShortcutEvents(),
                    focusNode: _editorFocusNode,
                    footer: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _focusEditorAtEnd,
                      child: const SizedBox(
                        width: double.infinity,
                        height: 280,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
    );
  }
}
