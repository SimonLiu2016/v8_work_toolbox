/// 听力练习统一工作区页面（主窗口内嵌）。
///
/// 布局：
/// - 顶栏（`WorkspaceHeader`）：标题、`[＋ 新建 ▾]`、`[词汇表]`、`[迷你播放器]`；
/// - 主体（自适应两栏/三栏 + 右侧全局精听抽屉 `TranscriptDrawer`）：
///   - 左栏（`LibrarySidebar`）：继续收听卡片、我的会议（真实会议 / 排练）、公开素材各场景、底部同步状态；
///   - 选中「我的会议」时为三栏：左导航 + 中间会议/排练列表 + 右侧会议/排练详情；
///   - 选中「公开素材」某场景时为两栏：左导航 + 场景片段列表（卡片内含摘要与进度，当前场景按需生成横幅）；
///   - 三类内容全空时主区域展示三张场景化入门引导卡片；
/// - 底栏（`WorkspacePlayerBar`）：持久播放控制条，点击标题跳回正在播放的条目，右侧 `[精听]` 开关全局文稿抽屉。
library;

import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../../services/app_paths.dart';
import '../../../theme/app_theme.dart';
import '../models/listening_models.dart';
import '../models/real_meeting_models.dart';
import '../models/rehearsal_models.dart';
import '../services/answer_generator.dart';
import '../services/clip_library.dart';
import '../services/listening_host.dart';
import '../services/listening_player_controller.dart';
import '../services/listening_progress_store.dart';
import '../services/listening_term_collector.dart';
import '../services/material_importer.dart';
import '../services/meeting_vocabulary_index.dart';
import '../services/public_library_controller.dart';
import '../services/real_meetings_controller.dart';
import '../services/rehearsals_controller.dart';
import '../services/rehearsal_text_generator.dart';
import '../services/role_voice_map.dart';
import '../services/task_tracker.dart';
import '../services/workspace_selection.dart';
import 'answer_composer_dialog.dart';
import 'library_sidebar.dart';
import 'material_import_panel.dart';
import 'public_scene_view.dart';
import 'real_meeting_views.dart';
import 'rehearsal_views.dart';
import 'transcript_drawer.dart';
import 'transcript_preview_dialog.dart';
import 'vocabulary_browser_dialog.dart';
import 'workspace_header.dart';
import 'workspace_player_bar.dart';

/// IT 会议听力练习工作区页面。
class ItMeetingListeningPage extends StatefulWidget {
  const ItMeetingListeningPage({super.key});

  @override
  State<ItMeetingListeningPage> createState() => _ItMeetingListeningPageState();
}

class _ItMeetingListeningPageState extends State<ItMeetingListeningPage> {
  late final TaskTracker _tracker;
  late final WorkspaceSelection _selection;
  late final PublicLibraryController _publicCtrl;
  late final RealMeetingsController _realCtrl;
  late final RehearsalsController _rehearsalCtrl;
  late final ListeningPlayerController _player;

  bool _loading = true;
  WorkspaceToastEvent? _latestToast;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _tracker = TaskTracker()..onToast = _handleToast;
    _selection = WorkspaceSelection()
      ..canLeaveRehearsal = _confirmLeaveUnsavedDraft;
    _player = ListeningHost.instance.controller;

    _publicCtrl = PublicLibraryController(
      library: ClipLibrary(AppPaths.itMeetingListeningDir),
      tracker: _tracker,
    );
    _realCtrl = RealMeetingsController(
      library: _publicCtrl.library,
      tracker: _tracker,
      onIndexChanged: () async {
        await _publicCtrl.reloadIndex();
      },
    );
    _rehearsalCtrl = RehearsalsController(
      library: _publicCtrl.library,
      tracker: _tracker,
      onIndexChanged: () async {
        await _publicCtrl.reloadIndex();
      },
    );

    _tracker.addListener(_onStateChanged);
    _selection.addListener(_onStateChanged);
    _publicCtrl.addListener(_onStateChanged);
    _realCtrl.addListener(_onStateChanged);
    _rehearsalCtrl.addListener(_onStateChanged);
    _player.addListener(_onStateChanged);

    _initializeWorkspace();
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    unawaited(_player.flushProgress());
    _tracker.removeListener(_onStateChanged);
    _selection.removeListener(_onStateChanged);
    _publicCtrl.removeListener(_onStateChanged);
    _realCtrl.removeListener(_onStateChanged);
    _rehearsalCtrl.removeListener(_onStateChanged);
    _player.removeListener(_onStateChanged);

    _tracker.dispose();
    _selection.dispose();
    _publicCtrl.dispose();
    _realCtrl.dispose();
    _rehearsalCtrl.dispose();
    super.dispose();
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  void _handleToast(WorkspaceToastEvent event) {
    if (!mounted) return;
    _toastTimer?.cancel();
    setState(() => _latestToast = event);
    _toastTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _latestToast = null);
      }
    });
  }

  // -------------------------------------------------------------------------
  // 启动恢复与默认选中回退链
  // -------------------------------------------------------------------------

  Future<void> _initializeWorkspace() async {
    await _publicCtrl.reloadIndex();
    await _rehearsalCtrl.loadRehearsals();
    await _realCtrl.loadMeetings();
    await _player.recorder.init();
    if (!mounted) return;

    // 1. 若有来自生词本的待回听请求，优先响应并播放。
    final pendingReplay = ListeningHost.instance.takePendingReplay();
    if (pendingReplay != null) {
      final target = _publicCtrl.index.byId(pendingReplay.clipId);
      if (target != null) {
        setState(() => _loading = false);
        await _jumpToClip(target);
        await _playClip(target);
        if (pendingReplay.offsetMs > 0) {
          await _player.seek(pendingReplay.offsetMs);
        }
        _tracker.emitToast('已跳转到 ${target.title}');
        return;
      } else {
        _tracker.emitToast('该素材已不在素材库中', isError: true);
      }
    }

    // 2. 若播放器已在后台持有某条素材，跟随该素材。
    final activeClip = _player.clip;
    if (activeClip != null) {
      _applyInitialSelectionForClip(activeClip);
      setState(() => _loading = false);
      return;
    }

    // 3. 尝试从上次播放记录静默恢复（暂停态，不自动发声）。
    Clip? resumedClip;
    var resumedOffset = 0;
    final last = _player.recorder.lastPlayed;
    if (last != null) {
      final candidate = _publicCtrl.index.byId(last.clipId);
      if (candidate != null && !candidate.isPlaceholder) {
        final file = _publicCtrl.library.audioFileFor(candidate);
        if (file.existsSync()) {
          resumedClip = candidate;
          resumedOffset = _player.recorder.offsetFor(
            candidate.id,
            currentDurationMs: candidate.durationMs,
          );
        }
      }
    }

    if (resumedClip != null) {
      _applyInitialSelectionForClip(resumedClip);
      final file = _publicCtrl.library.audioFileFor(resumedClip);
      _player.setQueue(_queueForClip(resumedClip), clipId: resumedClip.id);
      _player.preparePaused(
        resumedClip,
        offsetMs: resumedOffset,
        filePath: file.path,
      );
      setState(() => _loading = false);
      return;
    }

    // 4. 回退链：最近修改的会议/排练 → 第一个非空公开场景 → 默认真实会议分区。
    _applyFallbackInitialSelection();
    setState(() => _loading = false);
  }

  void _applyInitialSelectionForClip(Clip clip) {
    final src = clip.source.sourceId;
    if (src == 'real-meeting') {
      _selection.setSectionInitial(const WorkspaceNavTarget.realMeetings());
      _selection.setSelectedRealMeetingId(clip.id);
      return;
    }
    if (src == 'rehearsal') {
      final matId = _rehearsalCtrl.itemFor(clip.id)?.material.id ??
          (clip.id.startsWith('rehearsal_')
              ? clip.id.substring('rehearsal_'.length)
              : clip.id);
      _selection.setSectionInitial(const WorkspaceNavTarget.rehearsals());
      _selection.setSelectedRehearsalId(matId);
      _rehearsalCtrl.ensureDraftSession(matId);
      return;
    }
    _selection.setSectionInitial(WorkspaceNavTarget.publicScene(clip.scene));
    _selection.selectPublicClip(clip.id);
  }

  void _applyFallbackInitialSelection() {
    // 确保真实会议与排练都有默认选中第一项（若非空）
    if (_realCtrl.meetings.isNotEmpty) {
      _selection.setSelectedRealMeetingId(_realCtrl.meetings.first.id);
    }
    if (_rehearsalCtrl.items.isNotEmpty) {
      final firstId = _rehearsalCtrl.items.first.material.id;
      _selection.setSelectedRehearsalId(firstId);
      _rehearsalCtrl.ensureDraftSession(firstId);
    }

    final latestReal = _realCtrl.meetings.isNotEmpty
        ? _realCtrl.meetings.first.importedAt
        : null;
    final latestRehearsal = _rehearsalCtrl.items.isNotEmpty
        ? _rehearsalCtrl.items.first.lastModifiedAt
        : null;

    if (latestReal != null &&
        (latestRehearsal == null || !latestReal.isBefore(latestRehearsal))) {
      _selection.setSectionInitial(const WorkspaceNavTarget.realMeetings());
      return;
    }
    if (latestRehearsal != null) {
      _selection.setSectionInitial(const WorkspaceNavTarget.rehearsals());
      return;
    }
    final scenes = _publicCtrl.nonEmptyScenes();
    if (scenes.isNotEmpty) {
      _selection.setSectionInitial(WorkspaceNavTarget.publicScene(scenes.first));
      return;
    }
    _selection.setSectionInitial(const WorkspaceNavTarget.realMeetings());
  }

  // -------------------------------------------------------------------------
  // 播放与导航辅助
  // -------------------------------------------------------------------------

  List<Clip> _queueForClip(Clip clip) {
    final src = clip.source.sourceId;
    if (src == 'real-meeting' || src == 'rehearsal') {
      return [clip];
    }
    return _publicCtrl.clipsForScene(
      clip.scene,
      sourceId: _selection.selectedSourceId,
    );
  }

  Future<void> _playClip(Clip clip) async {
    final file = _publicCtrl.library.audioFileFor(clip);
    if (clip.isPlaceholder || !file.existsSync()) {
      _tracker.emitToast('该素材尚未生成音频', isError: true);
      return;
    }
    if (PublicLibraryController.isPublicClip(clip)) {
      _selection.selectPublicClip(clip.id);
    }
    _player.setQueue(_queueForClip(clip), clipId: clip.id);
    await _player.play(clip, filePath: file.path);
  }

  Future<void> _togglePlay() async {
    final clip = _player.clip ?? _fallbackClip;
    if (clip == null) return;
    if (_player.clip == null) {
      await _playClip(clip);
      return;
    }
    await _player.togglePlay();
  }

  Future<void> _next() async {
    final current = _player.clip;
    if (current != null &&
        (current.source.sourceId == 'real-meeting' ||
            current.source.sourceId == 'rehearsal')) {
      await _player.next();
      return;
    }
    final queue = _currentPublicSceneClips;
    if (queue.isEmpty) return;
    final idx =
        current == null ? -1 : queue.indexWhere((c) => c.id == current.id);
    final target = _playableIn(queue, idx, 1);
    if (target == null) {
      _tracker.emitToast('当前场景没有可播放的素材（请先生成音频）', isError: true);
      return;
    }
    _player.setQueue(queue, clipId: target.clip.id);
    await _player.play(target.clip, filePath: target.file.path);
    _selection.selectPublicClip(target.clip.id);
  }

  Future<void> _previous() async {
    final current = _player.clip;
    if (current != null &&
        (current.source.sourceId == 'real-meeting' ||
            current.source.sourceId == 'rehearsal')) {
      await _player.previous();
      return;
    }
    final queue = _currentPublicSceneClips;
    if (queue.isEmpty) return;
    final idx =
        current == null ? 0 : queue.indexWhere((c) => c.id == current.id);
    final target = _playableIn(queue, idx, -1);
    if (target == null) {
      _tracker.emitToast('当前场景没有可播放的素材（请先生成音频）', isError: true);
      return;
    }
    _player.setQueue(queue, clipId: target.clip.id);
    await _player.play(target.clip, filePath: target.file.path);
    _selection.selectPublicClip(target.clip.id);
  }

  ({Clip clip, File file})? _playableIn(List<Clip> queue, int from, int step) {
    for (var i = 0; i < queue.length; i++) {
      final idx =
          ((from + step * (i + 1)) % queue.length + queue.length) % queue.length;
      final clip = queue[idx];
      if (clip.isPlaceholder) continue;
      final file = _publicCtrl.library.audioFileFor(clip);
      if (!file.existsSync()) continue;
      return (clip: clip, file: file);
    }
    return null;
  }

  List<Clip> get _currentPublicSceneClips {
    final scene = _selection.section.scene;
    if (scene == null) return const [];
    return _publicCtrl.clipsForScene(
      scene,
      sourceId: _selection.selectedSourceId,
    );
  }

  Clip? get _fallbackClip {
    if (_selection.section.isRealMeetings) {
      final id = _selection.selectedRealMeetingId;
      return id == null ? null : _publicCtrl.index.byId(id);
    }
    if (_selection.section.isRehearsals) {
      final id = _selection.selectedRehearsalId;
      return _rehearsalCtrl.itemFor(id)?.clip;
    }
    final pubId = _selection.selectedPublicClipId;
    if (pubId != null) return _publicCtrl.index.byId(pubId);
    return null;
  }

  int get _currentTurnIndex {
    final clip = _player.clip ?? _fallbackClip;
    if (clip == null || clip.turns.isEmpty) return -1;
    final ms = _player.position.inMilliseconds;
    for (var i = 0; i < clip.turns.length; i++) {
      final t = clip.turns[i];
      if (ms >= t.startMs && ms < t.endMs) return i;
    }
    return clip.turns.length - 1;
  }

  Future<void> _jumpToClip(Clip clip) async {
    final ok = await _selection.jumpToClip(
      clip,
      resolveRehearsalMaterialId: (clipId) =>
          _rehearsalCtrl.itemFor(clipId)?.material.id,
    );
    if (ok && clip.source.sourceId == 'rehearsal') {
      final matId = _selection.selectedRehearsalId;
      if (matId != null) {
        _rehearsalCtrl.ensureDraftSession(matId);
      }
    }
  }

  ItemProgress? _progressForClip(String clipId) =>
      _player.recorder.state.items[clipId];

  ({Clip clip, int offsetMs, bool isPlaying})? get _continueListeningInfo {
    final active = _player.clip;
    if (active != null) {
      return (
        clip: active,
        offsetMs: _player.position.inMilliseconds,
        isPlaying: _player.isPlaying,
      );
    }
    final last = _player.recorder.lastPlayed;
    if (last == null) return null;
    final clip = _publicCtrl.index.byId(last.clipId);
    if (clip == null || clip.isPlaceholder) return null;
    final offset = _player.recorder.offsetFor(
      clip.id,
      currentDurationMs: clip.durationMs,
    );
    return (clip: clip, offsetMs: offset, isPlaying: false);
  }

  // -------------------------------------------------------------------------
  // 新建菜单与文件选择动作
  // -------------------------------------------------------------------------

  Future<void> _handleNewAction(WorkspaceNewAction action) async {
    switch (action) {
      case WorkspaceNewAction.importRealMeeting:
        await _pickAndImportRealMeeting();
      case WorkspaceNewAction.createRehearsal:
        await _pickAndImportRehearsalMaterial();
      case WorkspaceNewAction.syncPublicSources:
        final scenes = _publicCtrl.nonEmptyScenes(
          sourceId: _selection.selectedSourceId,
        );
        if (scenes.isNotEmpty && !_selection.section.isPublicScene) {
          await _selection.selectSection(
            WorkspaceNavTarget.publicScene(scenes.first),
          );
        }
        await _publicCtrl.syncSources();
        final afterScenes = _publicCtrl.nonEmptyScenes(
          sourceId: _selection.selectedSourceId,
        );
        if (afterScenes.isNotEmpty && !_selection.section.isPublicScene) {
          await _selection.selectSection(
            WorkspaceNavTarget.publicScene(afterScenes.first),
          );
        }
    }
  }

  Future<void> _pickAndImportRealMeeting() async {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择会议逐字稿（MD）',
      allowedExtensions: const ['md', 'markdown', 'txt'],
      type: FileType.custom,
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    final preview = await _realCtrl.parseTranscriptFile(path);
    if (preview == null || !mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => TranscriptPreviewDialog(preview: preview),
    );
    if (confirmed != true || !mounted) return;

    final meetingId = await _realCtrl.commitImport(preview);
    if (meetingId != null && mounted) {
      await _selection.selectRealMeeting(meetingId);
    }
  }

  Future<void> _pickAndImportRehearsalMaterial({
    String? replaceMaterialId,
  }) async {
    if (replaceMaterialId == null && _selection.section.isRehearsals) {
      final canLeave = await _confirmLeaveUnsavedDraft();
      if (!canLeave) return;
    }
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: '选择会议材料（MD / HTML）',
      allowedExtensions: MaterialImporter.supportedExtensions,
      type: FileType.custom,
    );
    final path = picked?.files.single.path;
    if (path == null) return;

    final id = await _rehearsalCtrl.importMaterialFromPath(
      path,
      replaceMaterialId: replaceMaterialId,
    );
    if (id != null && mounted) {
      _selection.setSectionInitial(const WorkspaceNavTarget.rehearsals());
      _selection.setSelectedRehearsalId(id);
      _rehearsalCtrl.ensureDraftSession(id);
    }
  }

  // -------------------------------------------------------------------------
  // 讲稿未保存保护与重新生成确认
  // -------------------------------------------------------------------------

  Future<bool> _confirmLeaveUnsavedDraft() async {
    if (!_rehearsalCtrl.hasUnsavedDraft) return true;
    if (!mounted) return true;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('有未保存的讲稿修改'),
        content: const Text('当前讲稿有尚未保存的编辑内容，离开前是否保存？'),
        actions: [
          TextButton(
            key: const ValueKey('unsaved-cancel-btn'),
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('取消'),
          ),
          TextButton(
            key: const ValueKey('unsaved-discard-btn'),
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: const Text('放弃'),
          ),
          FilledButton(
            key: const ValueKey('unsaved-save-btn'),
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (choice == 'save') {
      await _rehearsalCtrl.saveDraftEdits();
      return true;
    }
    if (choice == 'discard') {
      _rehearsalCtrl.discardDraftEdits();
      return true;
    }
    return false;
  }

  Future<void> _handleGenerateDraft(RehearsalStatusInfo info) async {
    if ((info.draft != null && info.draft!.isEdited) ||
        _rehearsalCtrl.hasUnsavedDraft) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重新生成讲稿'),
          content: const Text('当前讲稿包含手工修改的内容，重新生成将覆盖现有讲稿，是否继续？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              key: const ValueKey('confirm-regenerate-draft-btn'),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('覆盖并重新生成'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    await _rehearsalCtrl.generateDraft(info.material.id);
  }

  // -------------------------------------------------------------------------
  // 重命名、删除、Finder 与弹窗交互
  // -------------------------------------------------------------------------

  Future<void> _handleRealMeetingContextAction(
    RealMeetingItemSnapshot item,
    RealMeetingContextAction action,
  ) async {
    switch (action) {
      case RealMeetingContextAction.rename:
        await _promptRenameRealMeeting(item);
      case RealMeetingContextAction.revealInFinder:
        await _revealInFinder(item.meeting.sourcePath);
      case RealMeetingContextAction.delete:
        await _confirmDeleteRealMeeting(item);
    }
  }

  Future<void> _handleRehearsalContextAction(
    RehearsalStatusInfo item,
    RehearsalContextAction action,
  ) async {
    switch (action) {
      case RehearsalContextAction.rename:
        await _promptRenameRehearsal(item);
      case RehearsalContextAction.revealInFinder:
        await _revealInFinder(item.material.sourcePath);
      case RehearsalContextAction.delete:
        await _confirmDeleteRehearsal(item);
    }
  }

  Future<void> _revealInFinder(String path) async {
    if (path.isEmpty) return;
    try {
      await Process.run('open', ['-R', path]);
    } catch (e) {
      _tracker.emitToast('无法打开 Finder：$e', isError: true);
    }
  }

  Future<void> _promptRenameRealMeeting(RealMeetingItemSnapshot item) async {
    final settings = await _realCtrl.store.loadSettings(item.meeting.id);
    if (!mounted) return;
    final ctrl = TextEditingController(text: settings.displayTitle);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名真实会议'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '显示名称',
                hintText: item.meeting.title,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '留空则恢复文稿原标题「${item.meeting.title}」。原始文件不会被修改。',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await _realCtrl.renameMeeting(item.meeting.id, ctrl.text);
    }
  }

  Future<void> _promptRenameRehearsal(RehearsalStatusInfo item) async {
    final ctrl = TextEditingController(text: item.material.displayTitle ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名排练会议'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '显示名称',
                hintText: item.material.title,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '留空则恢复材料原标题「${item.material.title}」。原始文件不会被修改。',
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (saved == true) {
      await _rehearsalCtrl.renameRehearsal(item.material.id, ctrl.text);
    }
  }

  Future<void> _confirmDeleteRealMeeting(RealMeetingItemSnapshot item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除真实会议'),
        content: Text(
          '确定要删除「${item.displayTitle}」吗？\n删除后将移除合成音频、说话人设定与已插入的回答（原始 Markdown 文件不受影响）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-real-meeting-btn'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _realCtrl.deleteMeeting(item.meeting.id);
    if (_selection.selectedRealMeetingId == item.meeting.id) {
      _selection.setSelectedRealMeetingId(
        _realCtrl.meetings.isEmpty ? null : _realCtrl.meetings.first.id,
      );
    }
  }

  Future<void> _confirmDeleteRehearsal(RehearsalStatusInfo item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除排练会议'),
        content: Text(
          '确定要删除「${item.material.effectiveTitle}」吗？\n删除后将移除讲稿、剧本与合成音频（原始材料文件不受影响）。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-rehearsal-btn'),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _rehearsalCtrl.deleteRehearsal(item.material.id);
    if (_selection.selectedRehearsalId == item.material.id) {
      final nextId = _rehearsalCtrl.items.isEmpty
          ? null
          : _rehearsalCtrl.items.first.material.id;
      _selection.setSelectedRehearsalId(nextId);
      if (nextId != null) {
        _rehearsalCtrl.ensureDraftSession(nextId);
      }
    }
  }

  Future<void> _openMyIdentity() async {
    final identity = await _realCtrl.loadMyIdentity();
    if (!mounted) return;
    final nameCtrl = TextEditingController(text: identity.name);
    var voiceId = identity.voiceId;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('我的身份'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: '显示名',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: voiceId,
                decoration: const InputDecoration(
                  labelText: '音色',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final v in VoicePool.all)
                    DropdownMenuItem(value: v.id, child: Text(v.label)),
                ],
                onChanged: (v) => setLocal(() => voiceId = v ?? voiceId),
              ),
              const SizedBox(height: 8),
              const Text(
                '跨所有真实会议恒等；与排练会议里的「我」同一音色。已插入的历史回答不会被改名。',
                style: TextStyle(fontSize: 11),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) {
      await _realCtrl.saveMyIdentity(
        MyIdentity(
          name: nameCtrl.text.trim().isEmpty
              ? MyIdentity.defaultName
              : nameCtrl.text.trim(),
          voiceId: voiceId,
        ),
      );
    }
  }

  Future<void> _openVocabulary() async {
    final index = await _realCtrl.refreshVocabulary();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => VocabularyBrowserDialog(
        index: index,
        onJump: (posting) {
          Navigator.pop(context);
          _jumpToPosting(posting);
        },
      ),
    );
  }

  Future<void> _jumpToPosting(VocabularyPosting posting) async {
    final clip = _publicCtrl.index.byId(posting.meetingId);
    if (clip == null) {
      _tracker.emitToast('该会议的音频尚未生成', isError: true);
      return;
    }
    await _selection.selectRealMeeting(clip.id);
    _selection.setTranscriptDrawerOpen(true);
    await _playClip(clip);
    final original =
        clip.turns.where((t) => t.role != InsertedAnswer.roleMarker).toList();
    if (posting.turnIndex < original.length) {
      await _player.seek(original[posting.turnIndex].startMs);
    }
    _tracker.emitToast('已跳转到 ${clip.title} 第 ${posting.turnIndex + 1} 轮');
  }

  Future<void> _collectTerm(Clip clip, SpeakerTurn turn, String term) async {
    try {
      final id = await ListeningTermCollector().collect(
        clip: clip,
        turn: turn,
        term: term,
        materialDir: AppPaths.itMeetingListeningDir,
        termAudioDir: AppPaths.itMeetingTermAudioDir,
      );
      _tracker.emitToast('已收藏术语「$term」，可在生词本中查看出处');
      debugPrint('[ItMeetingListening] 术语已收藏: $id');
    } catch (e) {
      _tracker.emitToast('收藏失败：$e', isError: true);
    }
  }

  // -------------------------------------------------------------------------
  // 真实会议回答插入与编辑（在全局精听抽屉内触发）
  // -------------------------------------------------------------------------

  RealMeetingItemSnapshot? get _activeRealMeetingForTranscript {
    final clip = _player.clip ?? _fallbackClip;
    if (clip != null && clip.source.sourceId == 'real-meeting') {
      return _realCtrl.snapshotFor(clip.id);
    }
    return _realCtrl.snapshotFor(_selection.selectedRealMeetingId);
  }

  Future<void> _openAnswerComposer(int clipTurnIndex) async {
    final snap = _activeRealMeetingForTranscript;
    final clip = _player.clip ?? _fallbackClip;
    if (snap == null || clip == null) return;

    final original =
        clip.turns.where((t) => t.role != InsertedAnswer.roleMarker).toList();
    if (clipTurnIndex >= original.length) return;
    final turn = original[clipTurnIndex];
    final meetingTurn = snap.meeting.turns.firstWhere(
      (t) => t.text == turn.rawText,
      orElse: () => snap.meeting.turns.first,
    );
    await _launchAnswerComposer(snap, meetingTurn);
  }

  Future<void> _launchAnswerComposer(
    RealMeetingItemSnapshot snap,
    MeetingTurn turn,
  ) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AnswerComposerDialog(
        generator: AnswerGenerator(SlotTextGenerator()),
        meeting: snap.meeting,
        questionTurnIndex: turn.index,
        questionSpeaker:
            snap.speakers[turn.slotId]?.displayName ?? turn.slotId,
        questionText: turn.text,
        onInsert: (textEn, textZh) => _realCtrl.insertAnswer(
          meetingId: snap.meeting.id,
          questionTurnIndex: turn.index,
          textEn: textEn,
          textZh: textZh,
        ),
      ),
    );
    if (result == true && mounted) {
      final refreshed = _publicCtrl.index.byId(snap.meeting.id);
      if (refreshed != null && _player.clip?.id == refreshed.id) {
        final file = _publicCtrl.library.audioFileFor(refreshed);
        _player.preparePaused(
          refreshed,
          offsetMs: _player.position.inMilliseconds,
          filePath: file.path,
        );
      }
    }
  }

  Future<void> _openAnswerActions(SpeakerTurn turn) async {
    final snap = _activeRealMeetingForTranscript;
    if (snap == null) return;
    final answers = await _realCtrl.loadAnswers(snap.meeting.id);
    final matches = answers.where((a) => a.textEn == turn.rawText).toList();
    if (matches.isEmpty || !mounted) return;
    final answer = matches.first;

    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, size: 18),
              title: const Text('修改回答文本'),
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded, size: 18),
              title: const Text('重新生成（关掉后重新提问）'),
              subtitle: const Text('用同一个提问再生成一版，插入后可对比保留哪一版'),
              onTap: () => Navigator.pop(ctx, 'regen'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, size: 18),
              title: const Text('删除这条回答'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;

    if (action == 'delete') {
      await _realCtrl.deleteAnswer(snap.meeting.id, answer.id);
      return;
    }

    if (action == 'edit') {
      final ctrl = TextEditingController(text: answer.textEn);
      final saved = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('修改回答'),
          content: TextField(
            controller: ctrl,
            maxLines: 6,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存并重新合成'),
            ),
          ],
        ),
      );
      if (saved == true) {
        await _realCtrl.updateAnswerText(snap.meeting.id, answer.id, ctrl.text);
      }
      return;
    }

    final questionTurn = snap.meeting.turns.firstWhere(
      (t) => t.index == answer.questionTurnIndex,
      orElse: () => snap.meeting.turns.first,
    );
    await _launchAnswerComposer(snap, questionTurn);
  }

  // -------------------------------------------------------------------------
  // 构建视图
  // -------------------------------------------------------------------------

  bool get _isAllEmpty =>
      _publicCtrl.publicClips.isEmpty &&
      _realCtrl.meetings.isEmpty &&
      _rehearsalCtrl.items.isEmpty;

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final bg = isDark ? context.bgContent : AppTheme.lightBgContent;
    final border = isDark ? context.borderSubtle : AppTheme.lightBorderSubtle;
    final textPrimary =
        isDark ? context.textPrimary : AppTheme.lightTextPrimary;
    final textSecondary =
        isDark ? context.textSecondary : AppTheme.lightTextSecondary;
    final accent = context.accentText;

    final publicScenes = [
      for (final s in _publicCtrl.nonEmptyScenes(
        sourceId: _selection.selectedSourceId,
      ))
        (
          s,
          _publicCtrl.clipsForScene(
            s,
            sourceId: _selection.selectedSourceId,
          ),
        ),
    ];

    final activeOrFallbackClip = _player.clip ?? _fallbackClip;

    return Material(
      color: bg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          WorkspaceHeader(
            onNewAction: _handleNewAction,
            onOpenVocabulary: _openVocabulary,
            onOpenMiniPlayer: () => ListeningHost.instance.openMiniWindow(),
          ),
          if (_latestToast != null)
            _buildToastBanner(
              context,
              _latestToast!,
              isDark,
              textSecondary,
              accent,
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final wideScreen = constraints.maxWidth >= 960;
                      final drawerOpen = _selection.transcriptDrawerOpen;

                      final drawerWidget = TranscriptDrawer(
                        clip: activeOrFallbackClip,
                        currentTurnIndex: _currentTurnIndex,
                        onClose: () =>
                            _selection.setTranscriptDrawerOpen(false),
                        onSeekToTurn: (startMs) {
                          if (_player.clip != null) {
                            _player.seek(startMs);
                          }
                        },
                        onCollectTerm: _collectTerm,
                        onOpenAnswerComposer: _openAnswerComposer,
                        onOpenAnswerActions: _openAnswerActions,
                      );

                      final mainWorkspace = Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          LibrarySidebar(
                            selectedSection: _selection.section,
                            onSelectSection: (target) async {
                              final ok =
                                  await _selection.selectSection(target);
                              if (ok &&
                                  target.isRehearsals &&
                                  _selection.selectedRehearsalId != null) {
                                _rehearsalCtrl.ensureDraftSession(
                                  _selection.selectedRehearsalId!,
                                );
                              }
                            },
                            realMeetingCount: _realCtrl.meetings.length,
                            rehearsalCount: _rehearsalCtrl.items.length,
                            publicScenes: publicScenes,
                            totalPendingPublicCount:
                                _publicCtrl.allPendingClips.length,
                            onBakeAllPublic: () => _publicCtrl.bakePending(),
                            onSyncPublic: () => _publicCtrl.syncSources(),
                            syncTask: _tracker.entryFor(
                              WorkspaceTaskKind.publicSync,
                              'all',
                            ),
                            bakeAllTask: _tracker.entryFor(
                              WorkspaceTaskKind.publicBake,
                              'all',
                            ),
                            continueListening: _continueListeningInfo,
                            onTapContinueListening: () async {
                              final info = _continueListeningInfo;
                              if (info == null) return;
                              await _jumpToClip(info.clip);
                              await _togglePlay();
                            },
                          ),
                          VerticalDivider(width: 1, color: border),
                          Expanded(
                            child: _isAllEmpty
                                ? _buildOnboardingEmptyState(
                                    context,
                                    border,
                                    textPrimary,
                                    textSecondary,
                                    accent,
                                  )
                                : _buildSelectedSectionContent(
                                    context,
                                    border,
                                  ),
                          ),
                          if (drawerOpen && wideScreen) drawerWidget,
                        ],
                      );

                      if (!drawerOpen || wideScreen) {
                        return mainWorkspace;
                      }

                      // 窄屏（< 960px）下抽屉以右侧浮层覆盖展开
                      return Stack(
                        children: [
                          Positioned.fill(child: mainWorkspace),
                          Positioned.fill(
                            child: GestureDetector(
                              onTap: () =>
                                  _selection.setTranscriptDrawerOpen(false),
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.25),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: drawerWidget,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          WorkspacePlayerBar(
            player: _player,
            fallbackClip: _fallbackClip,
            transcriptOpen: _selection.transcriptDrawerOpen,
            onToggleTranscript: _selection.toggleTranscriptDrawer,
            onTogglePlay: _togglePlay,
            onPrevious: _previous,
            onNext: _next,
            onJumpToClip: _jumpToClip,
          ),
        ],
      ),
    );
  }

  Widget _buildToastBanner(
    BuildContext context,
    WorkspaceToastEvent toast,
    bool isDark,
    Color textSecondary,
    Color accent,
  ) {
    return Container(
      key: const ValueKey('workspace-toast-banner'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: toast.isError
          ? (isDark ? const Color(0xFF3A2226) : const Color(0xFFFDECEC))
          : (isDark ? context.bgCard : AppTheme.lightBgCard),
      child: Row(
        children: [
          Expanded(
            child: Text(
              toast.message,
              style: TextStyle(
                fontSize: 12,
                color: toast.isError ? Colors.redAccent : textSecondary,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
            icon: Icon(Icons.close_rounded, size: 14, color: textSecondary),
            onPressed: () => setState(() => _latestToast = null),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedSectionContent(BuildContext context, Color border) {
    final target = _selection.section;
    if (target.isPublicScene && target.scene != null) {
      final scene = target.scene!;
      return PublicSceneView(
        scene: scene,
        clips: _publicCtrl.clipsForScene(
          scene,
          sourceId: _selection.selectedSourceId,
        ),
        pendingClips: _publicCtrl.pendingForScene(
          scene,
          sourceId: _selection.selectedSourceId,
        ),
        availableSources: _publicCtrl.availableSources,
        selectedSourceId: _selection.selectedSourceId,
        onSourceChanged: _selection.setSourceFilter,
        onBakeScene: () => _publicCtrl.bakePending(
          scene: scene,
          sourceId: _selection.selectedSourceId,
        ),
        sceneBakeTask:
            _tracker.entryFor(WorkspaceTaskKind.publicBake, scene.id),
        playingClipId: _player.clip?.id,
        onPlayClip: _playClip,
        progressFor: _progressForClip,
      );
    }

    if (target.isRehearsals) {
      final selectedId = _selection.selectedRehearsalId ??
          (_rehearsalCtrl.items.isNotEmpty
              ? _rehearsalCtrl.items.first.material.id
              : null);
      final selectedItem = _rehearsalCtrl.itemFor(selectedId);
      final activeStep = selectedId != null
          ? _rehearsalCtrl.activeStepFor(selectedId)
          : RehearsalStep.material;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RehearsalListView(
            items: _rehearsalCtrl.filteredItems(_selection.rehearsalSearch),
            selectedId: selectedId,
            searchQuery: _selection.rehearsalSearch,
            onSearchChanged: _selection.setRehearsalSearch,
            onSelect: (id) async {
              final ok = await _selection.selectRehearsal(id);
              if (ok) {
                _rehearsalCtrl.ensureDraftSession(id);
              }
            },
            onCreateNew: () => _pickAndImportRehearsalMaterial(),
            onContextAction: _handleRehearsalContextAction,
            taskFor: (matId) =>
                _tracker.entryFor(WorkspaceTaskKind.rehearsalStep, matId),
            progressFor: _progressForClip,
          ),
          VerticalDivider(width: 1, color: border),
          Expanded(
            child: RehearsalDetail(
              item: selectedItem,
              activeStep: activeStep,
              onSelectStep: (step) {
                if (selectedId != null) {
                  _rehearsalCtrl.setActiveStep(selectedId, step);
                }
              },
              canRunStep: (step) => selectedId == null
                  ? false
                  : _rehearsalCtrl.canRunStep(selectedId, step),
              stepMessageFor: (step) => selectedId == null
                  ? null
                  : _rehearsalCtrl.stepMessageFor(selectedId, step),
              activeTask: selectedId == null
                  ? null
                  : _tracker.entryFor(
                      WorkspaceTaskKind.rehearsalStep,
                      selectedId,
                    ),
              isPlaying: selectedItem?.clip != null &&
                  _player.clip?.id == selectedItem!.clip!.id &&
                  _player.isPlaying,
              onRename: () {
                if (selectedItem != null) {
                  _promptRenameRehearsal(selectedItem);
                }
              },
              onTargetMinutesChanged: (minutes) {
                if (selectedId != null) {
                  _rehearsalCtrl.setTargetMinutes(selectedId, minutes);
                }
              },
              onReimportMaterial: () {
                if (selectedId != null) {
                  _pickAndImportRehearsalMaterial(
                    replaceMaterialId: selectedId,
                  );
                }
              },
              onGenerateDraft: () {
                if (selectedItem != null) {
                  _handleGenerateDraft(selectedItem);
                }
              },
              onGenerateScript: () {
                if (selectedId != null) {
                  _rehearsalCtrl.generateScript(selectedId);
                }
              },
              onBakeAudio: () {
                if (selectedId != null) {
                  _rehearsalCtrl.bakeAudio(selectedId);
                }
              },
              onPlay: () {
                final clip = selectedItem?.clip;
                if (clip != null) {
                  _playClip(clip);
                }
              },
              onOpenTranscriptDrawer: () =>
                  _selection.setTranscriptDrawerOpen(true),
              hasUnsavedDraft: _rehearsalCtrl.hasUnsavedDraft,
              workingDraftTitle: _rehearsalCtrl.workingDraftTitle,
              workingDraftSections: _rehearsalCtrl.workingDraftSections,
              onDraftTitleChanged: (title) {
                if (selectedId != null) {
                  _rehearsalCtrl.updateWorkingDraftTitle(selectedId, title);
                }
              },
              onDraftSectionChanged: (idx, {title, body}) {
                if (selectedId != null) {
                  _rehearsalCtrl.updateWorkingDraftSection(
                    selectedId,
                    idx,
                    title: title,
                    body: body,
                  );
                }
              },
              onAddDraftSection: () {
                if (selectedId != null) {
                  _rehearsalCtrl.addWorkingDraftSection(selectedId);
                }
              },
              onRemoveDraftSection: (idx) {
                if (selectedId != null) {
                  _rehearsalCtrl.removeWorkingDraftSection(selectedId, idx);
                }
              },
              onMoveDraftSection: (from, to) {
                if (selectedId != null) {
                  _rehearsalCtrl.moveWorkingDraftSection(selectedId, from, to);
                }
              },
              onSaveDraft: () => _rehearsalCtrl.saveDraftEdits(selectedId),
              onDiscardDraft: () =>
                  _rehearsalCtrl.discardDraftEdits(selectedId),
            ),
          ),
        ],
      );
    }

    // 默认：真实会议三栏视图
    final selectedId = _selection.selectedRealMeetingId ??
        (_realCtrl.meetings.isNotEmpty ? _realCtrl.meetings.first.id : null);
    final selectedSnap = _realCtrl.snapshotFor(selectedId);
    final publishedClip =
        selectedId == null ? null : _publicCtrl.index.byId(selectedId);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RealMeetingListView(
          items: _realCtrl.filteredSnapshots(_selection.realMeetingSearch),
          selectedId: selectedId,
          searchQuery: _selection.realMeetingSearch,
          onSearchChanged: _selection.setRealMeetingSearch,
          onSelect: (id) => _selection.selectRealMeeting(id),
          onImportNew: _pickAndImportRealMeeting,
          onContextAction: _handleRealMeetingContextAction,
          bakeTaskFor: (id) =>
              _tracker.entryFor(WorkspaceTaskKind.realMeetingBake, id),
          progressFor: _progressForClip,
        ),
        VerticalDivider(width: 1, color: border),
        Expanded(
          child: RealMeetingDetail(
            snapshot: selectedSnap,
            publishedClip: publishedClip,
            isPlaying: publishedClip != null &&
                _player.clip?.id == publishedClip.id &&
                _player.isPlaying,
            activeTask: selectedId == null
                ? null
                : _tracker.entryFor(
                    WorkspaceTaskKind.realMeetingBake,
                    selectedId,
                  ),
            onRunPrimaryAction: () {
              if (selectedId != null) {
                _realCtrl.runPrimaryAction(selectedId);
              }
            },
            onCancelBake: () {
              if (selectedId != null) {
                _realCtrl.requestCancelBake(selectedId);
              }
            },
            onPlay: () {
              if (publishedClip != null) {
                _playClip(publishedClip);
              }
            },
            onOpenTranscriptDrawer: () =>
                _selection.setTranscriptDrawerOpen(true),
            onRenameMeeting: () {
              if (selectedSnap != null) {
                _promptRenameRealMeeting(selectedSnap);
              }
            },
            onOpenIdentity: _openMyIdentity,
            onRenameSpeaker: (slotId, name) async {
              if (selectedId != null) {
                await _realCtrl.renameSpeaker(selectedId, slotId, name);
              }
            },
            onVoiceChanged: (slotId, voiceId) async {
              if (selectedId != null) {
                await _realCtrl.setSpeakerVoice(selectedId, slotId, voiceId);
              }
            },
            onToggleMe: (slotId, isMe) async {
              if (selectedId != null) {
                await _realCtrl.toggleSpeakerIsMe(selectedId, slotId, isMe);
              }
            },
            onMergeSpeaker: (fromSlot, intoSlot) async {
              if (selectedId != null) {
                await _realCtrl.mergeSpeaker(selectedId, fromSlot, intoSlot);
              }
            },
            onUnmergeSpeaker: (slotId) async {
              if (selectedId != null) {
                await _realCtrl.unmergeSpeaker(selectedId, slotId);
              }
            },
          ),
        ),
      ],
    );
  }

  /// 首次全空状态下的三张场景化入门引导卡片。
  Widget _buildOnboardingEmptyState(
    BuildContext context,
    Color border,
    Color textPrimary,
    Color textSecondary,
    Color accent,
  ) {
    return Center(
      key: const ValueKey('onboarding-empty-state'),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.headphones_outlined, size: 38, color: accent),
            const SizedBox(height: 10),
            Text(
              '选择你想开始的听力练习方式',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '你可以同步职场英语公开短对话，也可以用自己的会议材料做会前排练或会后复盘',
              style: TextStyle(fontSize: 12, color: textSecondary),
            ),
            const SizedBox(height: 20),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                _buildOnboardingCard(
                  context,
                  key: const ValueKey('onboarding-card-public'),
                  icon: Icons.cloud_download_outlined,
                  title: '随便听听',
                  subtitle: '从源站同步 1-3 分钟的 IT 职场英语对话碎片，支持后台连续循环磨耳朵',
                  actionLabel: '同步公开素材',
                  onPressed: () =>
                      _handleNewAction(WorkspaceNewAction.syncPublicSources),
                  border: border,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  accent: accent,
                ),
                _buildOnboardingCard(
                  context,
                  key: const ValueKey('onboarding-card-rehearsal'),
                  icon: Icons.campaign_outlined,
                  title: '准备会议',
                  subtitle: '导入周会或专项汇报材料（MD/HTML），自动生成英文讲稿与 5 角色 30-60 分钟模拟问答',
                  actionLabel: '新建会议排练',
                  onPressed: () =>
                      _handleNewAction(WorkspaceNewAction.createRehearsal),
                  border: border,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  accent: accent,
                ),
                _buildOnboardingCard(
                  context,
                  key: const ValueKey('onboarding-card-real-meeting'),
                  icon: Icons.record_voice_over_outlined,
                  title: '复听会议',
                  subtitle: '导入真实会议逐字稿（MD），还原多位同事音色，针对提问生成并插入你的英文回答',
                  actionLabel: '导入真实会议',
                  onPressed: () =>
                      _handleNewAction(WorkspaceNewAction.importRealMeeting),
                  border: border,
                  textPrimary: textPrimary,
                  textSecondary: textSecondary,
                  accent: accent,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOnboardingCard(
    BuildContext context, {
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required String actionLabel,
    required VoidCallback onPressed,
    required Color border,
    required Color textPrimary,
    required Color textSecondary,
    required Color accent,
  }) {
    return Container(
      key: key,
      width: 220,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: border),
        borderRadius: AppTheme.borderRadiusSmall,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 24, color: accent),
          const SizedBox(height: 10),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, height: 1.4, color: textSecondary),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: onPressed,
              child: Text(actionLabel, style: const TextStyle(fontSize: 12)),
            ),
          ),
        ],
      ),
    );
  }
}
