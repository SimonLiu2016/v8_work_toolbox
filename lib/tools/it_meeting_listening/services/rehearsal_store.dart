/// 排练会议三阶段产物的落盘（材料 / 讲稿 / 剧本）。
///
/// **为什么三个阶段各存一个文件**（design D8）：讲稿改了剧本要重生成，剧本改了
/// 音频要重烘，但材料始终不变。合成一个文件会让任何一步的重跑都丢掉另外两步
/// 的产物——用户改一次讲稿就要重烘 280 轮语音，那是 11 分钟白等。
///
/// 目录布局：
///
/// ```
/// rehearsal/
///   materials/<materialId>.json     导入的材料
///   drafts/<materialId>.json        讲稿（每个材料一份，覆盖写）
///   scripts/<materialId>.json       剧本（每个材料一份，覆盖写）
/// ```
///
/// 用 materialId 做文件名而不是自增 id：同一份材料重复导入覆盖旧产物，磁盘上
/// 不会堆出几十份没人看的副本。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../services/app_paths.dart';
import '../models/rehearsal_models.dart';
import 'clip_library.dart';
import 'rehearsal_baker.dart';

/// 排练会议中间产物存储。
class RehearsalStore {
  RehearsalStore({Directory? root})
      : _root = root ?? AppPaths.itMeetingRehearsalDir;

  final Directory _root;

  Directory get _materialsDir => Directory(p.join(_root.path, 'materials'));
  Directory get _draftsDir => Directory(p.join(_root.path, 'drafts'));
  Directory get _scriptsDir => Directory(p.join(_root.path, 'scripts'));

  File _materialFile(String materialId) =>
      File(p.join(_materialsDir.path, '$materialId.json'));
  File _draftFile(String materialId) =>
      File(p.join(_draftsDir.path, '$materialId.json'));
  File _scriptFile(String materialId) =>
      File(p.join(_scriptsDir.path, '$materialId.json'));

  /// 原子写：先写临时文件再 rename。
  ///
  /// 写一半断电会让 JSON 截断，下次读取整个产物丢失。rename 在同一文件系统内
  /// 是原子的。
  Future<void> _writeAtomic(File file, Map<String, dynamic> json) async {
    file.parent.createSync(recursive: true);
    final tmp = File('${file.path}.tmp');
    tmp.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(json),
      flush: true,
    );
    tmp.renameSync(file.path);
  }

  /// 读一个 JSON 文件，损坏或缺失时返回 null（降级而不是崩溃）。
  Future<Map<String, dynamic>?> _readJson(File file) async {
    if (!file.existsSync()) return null;
    try {
      final text = file.readAsStringSync();
      if (text.trim().isEmpty) return null;
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------
  // 材料
  // ---------------------------------------------------------------------

  Future<void> saveMaterial(RehearsalMaterial material) =>
      _writeAtomic(_materialFile(material.id), material.toJson());

  Future<RehearsalMaterial?> loadMaterial(String materialId) async {
    final json = await _readJson(_materialFile(materialId));
    return json == null ? null : RehearsalMaterial.fromJson(json);
  }

  /// 全部已导入材料（按导入时间倒序，新的在前）。
  Future<List<RehearsalMaterial>> listMaterials() async {
    final dir = _materialsDir;
    if (!dir.existsSync()) return const [];
    final out = <RehearsalMaterial>[];
    for (final entity in dir.listSync()) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      try {
        final json = jsonDecode(entity.readAsStringSync());
        out.add(RehearsalMaterial.fromJson(
            Map<String, dynamic>.from(json as Map)));
      } catch (_) {
        // 单个材料损坏不影响列表的其余部分。
      }
    }
    out.sort((a, b) => b.importedAt.compareTo(a.importedAt));
    return out;
  }

  // ---------------------------------------------------------------------
  // 讲稿
  // ---------------------------------------------------------------------

  Future<void> saveDraft(SpeechDraft draft) =>
      _writeAtomic(_draftFile(draft.materialId), draft.toJson());

  Future<SpeechDraft?> loadDraft(String materialId) async {
    final json = await _readJson(_draftFile(materialId));
    return json == null ? null : SpeechDraft.fromJson(json);
  }

  // ---------------------------------------------------------------------
  // 讲稿语音
  // ---------------------------------------------------------------------

  /// 讲稿语音产物文件（每个材料一份，覆盖写）。
  File _draftAudioFile(String materialId) =>
      File(p.join(_root.path, 'draft_audio', '$materialId.json'));

  /// 保存讲稿语音的各节结果。
  Future<void> saveDraftAudio(DraftBakeResult result) =>
      _writeAtomic(_draftAudioFile(result.materialId), {
        'materialId': result.materialId,
        'draftId': result.draftId,
        'voice': result.voice,
        'sections': result.sections.map((s) => s.toJson()).toList(),
        'failures': result.failures.map((k, v) => MapEntry('$k', v)),
      });

  /// 读取讲稿语音的各节结果。
  Future<DraftBakeResult?> loadDraftAudio(String materialId) async {
    final json = await _readJson(_draftAudioFile(materialId));
    if (json == null) return null;
    return DraftBakeResult(
      materialId: json['materialId'] as String? ?? materialId,
      draftId: json['draftId'] as String? ?? '',
      voice: json['voice'] as String? ?? '',
      sections: ((json['sections'] as List?) ?? const [])
          .map((e) => DraftSectionResult.fromJson(
              Map<String, dynamic>.from(e as Map)))
          .toList(),
      failures: ((json['failures'] as Map?) ?? const {}).map(
        (k, v) => MapEntry(int.tryParse('$k') ?? 0, v as String? ?? ''),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // 剧本
  // ---------------------------------------------------------------------

  Future<void> saveScript(MeetingScript script) =>
      _writeAtomic(_scriptFile(script.materialId), script.toJson());

  Future<MeetingScript?> loadScript(String materialId) async {
    final json = await _readJson(_scriptFile(materialId));
    return json == null ? null : MeetingScript.fromJson(json);
  }

  /// 更新剧本里的轮次时间戳（合成后回填）或失败标记。
  ///
  /// 合成 280 轮要几分钟，中途失败时把已成功的轮次时间写回去，用户就不必从头
  /// 再烘。
  Future<void> saveScriptTurns(
      String materialId, List<ScriptTurn> turns) async {
    final script = await loadScript(materialId);
    if (script == null) return;
    await _writeAtomic(
      _scriptFile(materialId),
      script.copyWith(turns: turns).toJson(),
    );
  }

  /// 删除一场排练及其全部关联产物（材料、讲稿、剧本、讲稿音频、逐回合缓存、整场音频与索引项）。
  Future<void> deleteMaterial(
    String materialId, {
    ClipLibrary? library,
    Directory? materialDir,
    Directory? cacheDir,
  }) async {
    final clipId = RehearsalStatusInfo.clipIdFor(materialId);
    final draftAudio = await loadDraftAudio(materialId);

    for (final f in [
      _materialFile(materialId),
      _draftFile(materialId),
      _scriptFile(materialId),
      _draftAudioFile(materialId),
    ]) {
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }

    final matDir = materialDir ?? _tryDefaultMaterialDir();
    if (matDir != null && await matDir.exists()) {
      final mainAudio = File(p.join(matDir.path, '$clipId.mp3'));
      if (await mainAudio.exists()) {
        try {
          await mainAudio.delete();
        } catch (_) {}
      }
      if (draftAudio != null) {
        for (final sec in draftAudio.sections) {
          if (sec.audioPath.isEmpty) continue;
          final sf = File(p.join(matDir.path, sec.audioPath));
          if (await sf.exists()) {
            try {
              await sf.delete();
            } catch (_) {}
          }
        }
      }
    }

    final cDir = cacheDir ?? _tryDefaultCacheDir();
    if (cDir != null && await cDir.exists()) {
      final draftPrefix = 'draft_${materialId}_';
      final turnPrefix = '${clipId}_';
      await for (final entity in cDir.list()) {
        if (entity is! File) continue;
        final name = p.basename(entity.path);
        if (name.startsWith(draftPrefix) || name.startsWith(turnPrefix)) {
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
    }

    if (library != null) {
      final index = await library.loadIndex();
      final filtered = index.clips.where((c) => c.id != clipId).toList();
      if (filtered.length != index.clips.length) {
        await library.rebuildIndex(filtered);
      }
    }
  }

  Directory? _tryDefaultMaterialDir() {
    try {
      return AppPaths.itMeetingListeningDir;
    } catch (_) {
      return null;
    }
  }

  Directory? _tryDefaultCacheDir() {
    try {
      return AppPaths.itMeetingListeningCacheDir;
    } catch (_) {
      return null;
    }
  }
}
