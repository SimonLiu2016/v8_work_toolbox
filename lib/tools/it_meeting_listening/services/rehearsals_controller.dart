/// 多场排练控制器：列表管理、四步管线、讲稿编辑与未保存保护、按场目标时长、重命名与删除。
///
/// 满足 `specs/listening-practice-workspace/spec.md` 的多场排练与讲稿编辑要求：
/// - 每场排练独立保存材料、讲稿、剧本、合成音频与目标时长（30 / 60 分钟）；
/// - 列表按最近修改时间倒序排列；
/// - 讲稿支持标题与各节增删改、上下移动，显式保存后生成新 `draft.id`，使现有剧本标记为"已过期"且不自动重生成；
/// - 离开有未保存修改的讲稿时可通过 `hasUnsavedDraft` 触发保存/放弃/取消提示。
library;

import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../services/app_paths.dart';
import '../../reader/services/tts_engine.dart';
import '../models/rehearsal_models.dart';
import '../ui/material_import_panel.dart';
import 'clip_library.dart';
import 'listening_host.dart';
import 'material_importer.dart';
import 'meeting_script_generator.dart';
import 'rehearsal_baker.dart';
import 'rehearsal_llm.dart';
import 'rehearsal_store.dart';
import 'rehearsal_text_generator.dart';
import 'speech_draft_generator.dart';
import 'task_tracker.dart';

/// 多场排练控制器。
class RehearsalsController extends ChangeNotifier {
  final RehearsalStore store;
  final ClipLibrary library;
  final TaskTracker tracker;
  final Future<void> Function()? onIndexChanged;
  final SpeechDraftGenerator Function() _draftGeneratorFactory;
  final MeetingScriptGenerator Function() _scriptGeneratorFactory;
  final TtsEngine Function() _ttsEngineFactory;

  List<RehearsalStatusInfo> _items = const [];
  final Map<String, RehearsalStep> _activeStepByMaterial = {};
  final Map<String, String?> _stepMessageByKey = {};

  // ---- 讲稿编辑工作区状态 ----
  String? _editingMaterialId;
  String _workingDraftTitle = '';
  List<DraftSection> _workingDraftSections = const [];
  bool _isDraftDirty = false;

  RehearsalsController({
    RehearsalStore? store,
    ClipLibrary? library,
    required this.tracker,
    this.onIndexChanged,
    SpeechDraftGenerator Function()? draftGeneratorFactory,
    MeetingScriptGenerator Function()? scriptGeneratorFactory,
    TtsEngine Function()? ttsEngineFactory,
  })  : store = store ?? RehearsalStore(),
        library = library ?? ListeningHost.instance.library,
        _draftGeneratorFactory = draftGeneratorFactory ??
            (() => SpeechDraftGeneratorImpl(SlotTextGenerator())),
        _scriptGeneratorFactory = scriptGeneratorFactory ??
            (() => MeetingScriptGeneratorImpl(SlotTextGenerator())),
        _ttsEngineFactory = ttsEngineFactory ?? (() => OpenAiTtsEngine());

  /// 全部排练条目（按最近修改时间倒序）。
  List<RehearsalStatusInfo> get items => _items;

  /// 是否存在尚未保存的讲稿编辑。
  bool get hasUnsavedDraft => _isDraftDirty;

  /// 当前正在编辑讲稿的排练 id。
  String? get editingMaterialId => _editingMaterialId;

  /// 当前讲稿编辑副本的标题。
  String get workingDraftTitle => _workingDraftTitle;

  /// 当前讲稿编辑副本的分节列表。
  List<DraftSection> get workingDraftSections => _workingDraftSections;

  /// 查找指定 `materialId`（或兼容 `rehearsal_<materialId>`）的排练摘要。
  RehearsalStatusInfo? itemFor(String? id) {
    if (id == null) return null;
    for (final item in _items) {
      if (item.material.id == id || item.clipId == id) return item;
    }
    return null;
  }

  /// 按搜索词过滤后的排练列表。
  List<RehearsalStatusInfo> filteredItems(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _items;
    return _items
        .where((it) =>
            it.material.effectiveTitle.toLowerCase().contains(q) ||
            it.material.title.toLowerCase().contains(q) ||
            it.material.fileName.toLowerCase().contains(q))
        .toList();
  }

  /// 获取某场排练当前选中的步骤页签。
  RehearsalStep activeStepFor(String materialId) {
    final explicit = _activeStepByMaterial[materialId];
    if (explicit != null) return explicit;
    final info = itemFor(materialId);
    if (info == null) return RehearsalStep.material;
    if (info.draft == null) return RehearsalStep.draft;
    if (info.script == null || info.isScriptStale) return RehearsalStep.script;
    return RehearsalStep.audio;
  }

  /// 切换某场排练当前查看的步骤。
  void setActiveStep(String materialId, RehearsalStep step) {
    if (_activeStepByMaterial[materialId] == step) return;
    _activeStepByMaterial[materialId] = step;
    notifyListeners();
  }

  /// 某场排练某一步的提示或错误信息。
  String? stepMessageFor(String materialId, RehearsalStep step) =>
      _stepMessageByKey['$materialId:${step.name}'];

  /// 某场排练某一步的前置条件是否满足。
  bool canRunStep(String materialId, RehearsalStep step) {
    final info = itemFor(materialId);
    if (info == null) return step == RehearsalStep.material;
    if (tracker.isRunning(WorkspaceTaskKind.rehearsalStep, materialId)) {
      return false;
    }
    return switch (step) {
      RehearsalStep.material => true,
      RehearsalStep.draft => true,
      RehearsalStep.script => info.draft != null,
      RehearsalStep.audio => info.script != null,
    };
  }

  /// 载入全部排练条目并按最近修改时间倒序排列。
  Future<void> loadRehearsals() async {
    try {
      final materials = await store.listMaterials();
      final index = await ListeningHost.instance.loadIndex();
      final loaded = <RehearsalStatusInfo>[];

      for (final mat in materials) {
        final draft = await store.loadDraft(mat.id);
        final script = await store.loadScript(mat.id);
        final clipId = RehearsalStatusInfo.clipIdFor(mat.id);
        final clip = index.byId(clipId);
        loaded.add(
          RehearsalStatusInfo(
            material: mat,
            draft: draft,
            script: script,
            clip: clip,
          ),
        );
      }

      loaded.sort((a, b) => b.lastModifiedAt.compareTo(a.lastModifiedAt));
      _items = loaded;

      // 若当前编辑中的排练没有脏修改，同步其工作副本。
      if (_editingMaterialId != null && !_isDraftDirty) {
        final current = itemFor(_editingMaterialId);
        if (current?.draft != null) {
          _syncWorkingDraftFrom(current!.draft!);
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint('[RehearsalsController] 载入排练列表失败: $e');
    }
  }

  // -------------------------------------------------------------------------
  // 讲稿编辑工作区
  // -------------------------------------------------------------------------

  /// 确保讲稿编辑工作区已针对 [materialId] 初始化。
  void ensureDraftSession(String materialId) {
    final info = itemFor(materialId);
    final draft = info?.draft;
    if (draft == null) {
      if (_editingMaterialId == materialId) {
        _editingMaterialId = null;
        _workingDraftTitle = '';
        _workingDraftSections = const [];
        _isDraftDirty = false;
      }
      return;
    }
    if (_editingMaterialId == materialId && _isDraftDirty) {
      return;
    }
    _editingMaterialId = materialId;
    _syncWorkingDraftFrom(draft);
  }

  void _syncWorkingDraftFrom(SpeechDraft draft) {
    _workingDraftTitle = draft.title;
    _workingDraftSections = List<DraftSection>.from(draft.sections);
    _isDraftDirty = false;
  }

  /// 修改讲稿标题（仅改工作副本，标记 dirty）。
  void updateWorkingDraftTitle(String materialId, String title) {
    ensureDraftSession(materialId);
    if (_workingDraftTitle == title) return;
    _workingDraftTitle = title;
    _isDraftDirty = true;
    notifyListeners();
  }

  /// 修改某一节的标题或正文（仅改工作副本，标记 dirty）。
  void updateWorkingDraftSection(
    String materialId,
    int index, {
    String? title,
    String? body,
  }) {
    ensureDraftSession(materialId);
    if (index < 0 || index >= _workingDraftSections.length) return;
    final current = _workingDraftSections[index];
    final next = DraftSection(
      title: title ?? current.title,
      body: body ?? current.body,
    );
    if (next.title == current.title && next.body == current.body) return;
    final list = List<DraftSection>.from(_workingDraftSections);
    list[index] = next;
    _workingDraftSections = list;
    _isDraftDirty = true;
    notifyListeners();
  }

  /// 新增一个讲稿节。
  void addWorkingDraftSection(
    String materialId, {
    String title = 'New Topic',
    String body = '',
  }) {
    ensureDraftSession(materialId);
    _workingDraftSections = [
      ..._workingDraftSections,
      DraftSection(title: title, body: body),
    ];
    _isDraftDirty = true;
    notifyListeners();
  }

  /// 删除一个讲稿节。
  void removeWorkingDraftSection(String materialId, int index) {
    ensureDraftSession(materialId);
    if (index < 0 || index >= _workingDraftSections.length) return;
    final list = List<DraftSection>.from(_workingDraftSections)..removeAt(index);
    _workingDraftSections = list;
    _isDraftDirty = true;
    notifyListeners();
  }

  /// 调整讲稿节顺序（上移/下移）。
  void moveWorkingDraftSection(String materialId, int fromIndex, int toIndex) {
    ensureDraftSession(materialId);
    if (fromIndex < 0 ||
        fromIndex >= _workingDraftSections.length ||
        toIndex < 0 ||
        toIndex >= _workingDraftSections.length ||
        fromIndex == toIndex) {
      return;
    }
    final list = List<DraftSection>.from(_workingDraftSections);
    final item = list.removeAt(fromIndex);
    list.insert(toIndex, item);
    _workingDraftSections = list;
    _isDraftDirty = true;
    notifyListeners();
  }

  /// 放弃未保存的讲稿修改，恢复为磁盘已保存版本。
  void discardDraftEdits([String? materialId]) {
    final targetId = materialId ?? _editingMaterialId;
    if (targetId == null) return;
    final draft = itemFor(targetId)?.draft;
    if (draft != null) {
      _editingMaterialId = targetId;
      _syncWorkingDraftFrom(draft);
    } else {
      _isDraftDirty = false;
    }
    notifyListeners();
  }

  /// 显式保存讲稿编辑：生成新 `draft.id` 并写入磁盘，使旧剧本自动标记为"已过期"（不自动重生成）。
  Future<SpeechDraft?> saveDraftEdits([String? materialId]) async {
    final targetId = materialId ?? _editingMaterialId;
    if (targetId == null) return null;
    final info = itemFor(targetId);
    final existing = info?.draft;
    if (existing == null) return null;

    final updated = existing.copyWithEdited(
      title: _workingDraftTitle.trim().isEmpty
          ? existing.title
          : _workingDraftTitle.trim(),
      sections: List<DraftSection>.from(_workingDraftSections),
    );
    await store.saveDraft(updated);
    _editingMaterialId = targetId;
    _syncWorkingDraftFrom(updated);
    await loadRehearsals();
    tracker.emitToast(
      info?.script != null ? '讲稿已保存（剧本已标记为基于旧讲稿，请按需重新生成）' : '讲稿已保存',
    );
    return updated;
  }

  // -------------------------------------------------------------------------
  // 新建、重命名、目标时长与删除
  // -------------------------------------------------------------------------

  /// 从文件路径导入材料并创建/更新排练条目。成功时返回 `material.id`。
  Future<String?> importMaterialFromPath(
    String path, {
    String? replaceMaterialId,
  }) async {
    try {
      var imported = await MaterialImporter.importFile(path);
      if (replaceMaterialId != null) {
        final prev = itemFor(replaceMaterialId)?.material;
        imported = RehearsalMaterial(
          id: replaceMaterialId,
          title: imported.title,
          sourcePath: imported.sourcePath,
          fileName: imported.fileName,
          text: imported.text,
          importedAt: DateTime.now(),
          displayTitle: prev?.displayTitle,
          targetMinutes: prev?.targetMinutes ?? 30,
        );
      }
      await store.saveMaterial(imported);
      _activeStepByMaterial[imported.id] = RehearsalStep.draft;
      await loadRehearsals();
      tracker.emitToast('已导入材料「${imported.effectiveTitle}」');
      return imported.id;
    } on MaterialImportException catch (e) {
      tracker.emitToast(e.message, isError: true);
      return null;
    } catch (e) {
      tracker.emitToast('导入材料失败：$e', isError: true);
      return null;
    }
  }

  /// 修改某场排练的目标时长（30 或 60 分钟，按场独立持久化）。
  Future<void> setTargetMinutes(String materialId, int minutes) async {
    final info = itemFor(materialId);
    if (info == null || info.material.targetMinutes == minutes) return;
    final updated = info.material.copyWith(targetMinutes: minutes);
    await store.saveMaterial(updated);
    await loadRehearsals();
  }

  /// 重命名某场排练（不修改原始文件；若已有合成片段则同步更新索引标题）。
  Future<void> renameRehearsal(String materialId, String newTitle) async {
    final info = itemFor(materialId);
    if (info == null) return;
    final trimmed = newTitle.trim();
    final updated = info.material.copyWith(
      displayTitle: trimmed,
      clearDisplayTitle: trimmed.isEmpty,
    );
    await store.saveMaterial(updated);

    final clipId = info.clipId;
    final index = await library.loadIndex();
    final existingClip = index.byId(clipId);
    if (existingClip != null) {
      final updatedClips = index.clips
          .map((c) =>
              c.id == clipId ? c.copyWith(title: updated.effectiveTitle) : c)
          .toList();
      await library.rebuildIndex(updatedClips);
      await onIndexChanged?.call();
    }

    await loadRehearsals();
    tracker.emitToast(
      trimmed.isEmpty ? '已恢复原材料标题' : '已重命名为「$trimmed」',
    );
  }

  /// 删除一场排练及其全部产物；若正在播放则先停止。
  Future<void> deleteRehearsal(
    String materialId, {
    Directory? materialDirOverride,
    Directory? cacheDirOverride,
  }) async {
    final clipId = RehearsalStatusInfo.clipIdFor(materialId);
    final hostPlayer = ListeningHost.instance.controller;
    if (hostPlayer.clip?.id == clipId) {
      await hostPlayer.stop();
    }
    if (_editingMaterialId == materialId) {
      _editingMaterialId = null;
      _isDraftDirty = false;
    }
    _activeStepByMaterial.remove(materialId);
    await store.deleteMaterial(
      materialId,
      library: library,
      materialDir: materialDirOverride,
      cacheDir: cacheDirOverride,
    );
    await onIndexChanged?.call();
    await loadRehearsals();
    tracker.emitToast('已删除该排练');
  }

  // -------------------------------------------------------------------------
  // 四步生成与合成管线
  // -------------------------------------------------------------------------

  /// 生成（或重新生成）讲稿。返回 null 表示成功，非 null 为错误原因。
  Future<String?> generateDraft(String materialId) async {
    final info = itemFor(materialId);
    if (info == null) return '未找到该排练材料';

    tracker.start(
      WorkspaceTaskKind.rehearsalStep,
      materialId,
      label: '正在生成讲稿…',
    );
    _stepMessageByKey['$materialId:${RehearsalStep.draft.name}'] = null;

    try {
      final draft = await _draftGeneratorFactory().generateDraft(info.material);
      await store.saveDraft(draft);
      _editingMaterialId = materialId;
      _syncWorkingDraftFrom(draft);
      _activeStepByMaterial[materialId] = RehearsalStep.draft;
      await loadRehearsals();
      tracker.complete(
        WorkspaceTaskKind.rehearsalStep,
        materialId,
        message: '讲稿已生成（共 ${draft.sections.length} 节）',
      );
      return null;
    } on DraftGenerationException catch (e) {
      _stepMessageByKey['$materialId:${RehearsalStep.draft.name}'] = e.message;
      tracker.fail(WorkspaceTaskKind.rehearsalStep, materialId, e.message);
      return e.message;
    } catch (e) {
      final msg = '生成讲稿失败：$e';
      _stepMessageByKey['$materialId:${RehearsalStep.draft.name}'] = msg;
      tracker.fail(WorkspaceTaskKind.rehearsalStep, materialId, msg);
      return msg;
    }
  }

  /// 生成（或重新生成）剧本。返回 null 表示成功，非 null 为提示或错误。
  Future<String?> generateScript(String materialId) async {
    final info = itemFor(materialId);
    if (info == null) return '未找到该排练材料';
    final draft = info.draft;
    if (draft == null) return '请先生成讲稿';

    tracker.start(
      WorkspaceTaskKind.rehearsalStep,
      materialId,
      label: '正在生成 5 角色剧本…',
    );
    _stepMessageByKey['$materialId:${RehearsalStep.script.name}'] = null;

    try {
      final script = await _scriptGeneratorFactory().generateScript(
        material: info.material,
        draft: draft,
        targetMinutes: info.material.targetMinutes,
      );
      await store.saveScript(script);
      _activeStepByMaterial[materialId] = RehearsalStep.script;
      await loadRehearsals();
      final warn = _scriptWarning(script);
      _stepMessageByKey['$materialId:${RehearsalStep.script.name}'] = warn;
      tracker.complete(
        WorkspaceTaskKind.rehearsalStep,
        materialId,
        message: warn ?? '剧本已生成（${script.turns.length} 轮）',
      );
      return null;
    } on ScriptTooShortWarning catch (w) {
      await store.saveScript(w.script);
      _activeStepByMaterial[materialId] = RehearsalStep.script;
      await loadRehearsals();
      final warn =
          '剧本 ${w.script.turns.length} 轮，预估 ${w.script.estimatedMs ~/ 60000} 分钟，短于目标区间（仍可使用）';
      _stepMessageByKey['$materialId:${RehearsalStep.script.name}'] = warn;
      tracker.complete(
        WorkspaceTaskKind.rehearsalStep,
        materialId,
        message: warn,
      );
      return null;
    } on ScriptGenerationException catch (e) {
      _stepMessageByKey['$materialId:${RehearsalStep.script.name}'] = e.message;
      tracker.fail(WorkspaceTaskKind.rehearsalStep, materialId, e.message);
      return e.message;
    } catch (e) {
      final msg = '生成剧本失败：$e';
      _stepMessageByKey['$materialId:${RehearsalStep.script.name}'] = msg;
      tracker.fail(WorkspaceTaskKind.rehearsalStep, materialId, msg);
      return msg;
    }
  }

  /// 合成排练语音（讲稿分节语音 + 5 角色整场语音）。
  Future<String?> bakeAudio(
    String materialId, {
    Directory? materialDirOverride,
    Directory? cacheDirOverride,
  }) async {
    final info = itemFor(materialId);
    if (info == null) return '未找到该排练材料';
    final draft = info.draft;
    final script = info.script;
    if (draft == null) return '请先生成讲稿';
    if (script == null) return '请先生成剧本';

    tracker.start(
      WorkspaceTaskKind.rehearsalStep,
      materialId,
      label: '正在合成讲稿语音（0/${draft.sections.length}）…',
      done: 0,
      total: script.turns.length,
    );
    _stepMessageByKey['$materialId:${RehearsalStep.audio.name}'] = null;

    final matDir = materialDirOverride ?? AppPaths.itMeetingListeningDir;
    final cacheDir = cacheDirOverride ?? AppPaths.itMeetingListeningCacheDir;
    final baker = RehearsalBaker(
      engine: _ttsEngineFactory(),
      materialDir: matDir,
      cacheDir: cacheDir,
    );

    try {
      final draftAudio = await baker.bakeDraft(
        draft,
        onProgress: (done, total, role) {
          tracker.updateProgress(
            WorkspaceTaskKind.rehearsalStep,
            materialId,
            done: done,
            total: total,
            label: '正在合成讲稿语音（$done/$total）…',
          );
        },
      );
      if (draftAudio.hasAudio) {
        await store.saveDraftAudio(draftAudio);
      }
    } catch (e) {
      debugPrint('[RehearsalsController] 讲稿语音合成失败: $e');
    }

    try {
      final result = await baker.bake(
        script.copyWith(title: info.material.effectiveTitle),
        onProgress: (done, total, role) {
          tracker.updateProgress(
            WorkspaceTaskKind.rehearsalStep,
            materialId,
            done: done,
            total: total,
            label: '正在合成整场语音（$done/$total）${role.isEmpty ? "" : " · $role"}…',
          );
        },
      );

      if (result.turns.isNotEmpty) {
        await store.saveScriptTurns(materialId, result.turns);
      }
      if (result.hasAudio && result.clip != null) {
        final index = await library.loadIndex();
        final merged = index.clips
            .where((c) => c.id != result.clip!.id)
            .toList()
          ..add(result.clip!.copyWith(title: info.material.effectiveTitle));
        await library.rebuildIndex(merged);
        await onIndexChanged?.call();
      }
      await loadRehearsals();

      if (!result.hasAudio || result.clip == null) {
        final err =
            '整场合成失败：${result.failures.values.take(3).join("；")}';
        _stepMessageByKey['$materialId:${RehearsalStep.audio.name}'] = err;
        tracker.fail(WorkspaceTaskKind.rehearsalStep, materialId, err);
        return err;
      }

      final failedCount = result.failures.length;
      if (failedCount > 0) {
        final msg = '整场合成完成，$failedCount 轮失败（已用静音占位，可重试）';
        _stepMessageByKey['$materialId:${RehearsalStep.audio.name}'] = msg;
        tracker.fail(WorkspaceTaskKind.rehearsalStep, materialId, msg);
        return msg;
      }

      tracker.complete(
        WorkspaceTaskKind.rehearsalStep,
        materialId,
        message: '「${info.material.effectiveTitle}」语音合成完成',
      );
      return null;
    } catch (e) {
      final err = '合成失败：$e';
      _stepMessageByKey['$materialId:${RehearsalStep.audio.name}'] = err;
      tracker.fail(WorkspaceTaskKind.rehearsalStep, materialId, err);
      return err;
    }
  }

  static String? _scriptWarning(MeetingScript script) {
    if (script.isWithinTargetRange) return null;
    final minutes = script.estimatedMs ~/ 60000;
    if (minutes < 30) return '剧本预估 $minutes 分钟，短于 30 分钟';
    return '剧本预估 $minutes 分钟，长于 1 小时';
  }
}
