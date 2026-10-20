import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../services/app_paths.dart';
import 'ffmpeg_composer.dart';

/// 资产类型。
///
/// 图片与视频分开：它们的引用方式完全不同——图片进角色/场景卡的参考图
/// 列表，视频进合成交付的时间线。合成一个 kind 会让消费侧到处分叉。
enum AssetKind {
  image('image', '图片'),
  clip('clip', '视频片段');

  final String id;
  final String label;

  const AssetKind(this.id, this.label);

  static AssetKind? fromId(String? id) {
    for (final k in values) {
      if (k.id == id) return k;
    }
    return null;
  }

  /// 资产文件的扩展名。图片固定 png——入库时统一转码，不保留原格式
  /// （原格式可能是 webp/heic，别的工具不一定认）。
  String get extension => this == image ? 'png' : 'mp4';
}

/// 资产来源。
enum AssetSource {
  /// 远端生成（用户付过费的那些）。
  remote('remote', '云端生成'),

  /// 本地导入（用户从外部丢进来的）。
  local('local', '本地导入');

  final String id;
  final String label;

  const AssetSource(this.id, this.label);

  static AssetSource? fromId(String? id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// 资产分类。
///
/// 与 [AssetKind] 是两个正交维度：kind 说"这是什么媒体形态"（图片还是视频），
/// category 说"它在制作流程里扮演什么角色"。同一个 png 可能是角色参考、
/// 关键帧或道具图——消费场景不同，筛选时用户要找的是后者。
///
/// 枚举而非自由文本：分类要做筛选器 UI，用户随意扩张会让筛选器退化成一个
/// 搜索框。新增值的成本是改代码，这是刻意保留的（design 决策 4）。
enum AssetCategory {
  character('character', '角色'),
  scene('scene', '场景'),
  prop('prop', '道具'),
  frame('frame', '关键帧'),
  clip('clip', '视频片段'),
  other('other', '其他');

  final String id;
  final String label;

  const AssetCategory(this.id, this.label);

  static AssetCategory? fromId(String? id) {
    for (final c in values) {
      if (c.id == id) return c;
    }
    return null;
  }
}

/// 一条资产记录。
///
/// **ID 是稳定标识**：文件名即 ID，`<id>.png` / `<id>.mp4`。不用语义 slug
/// ——中文文件名在跨平台/导出/shell 场景下都是麻烦源，本项目其他地方一律
/// 用 id。
class StudioAsset {
  final String id;
  final AssetKind kind;
  final AssetSource source;

  /// 自定义资产名称（可选，若未指定则显示 id）。
  final String? name;

  /// 视频资产海报封面帧路径（可选，相对或绝对路径）。
  final String? coverPath;

  /// 供应商标识（远端生成才有）。
  final String? providerId;

  /// 模型 id（远端生成才有）。
  final String? model;

  /// 生成提示词（远端生成才有）。
  final String? prompt;

  /// 来源调用记录的 localId。关联是**单向**的：资产 → 调用记录。
  ///
  /// 调用记录不反向记"我是否被收进资产库"——少一个方向的关联就少一类
  /// 两文件不一致。
  final String? sourceCallId;

  /// 最初产出路径（相对 AppSupport 根）。用于回望"这玩意本来是哪个分镜的"。
  final String? originPath;

  final int sizeBytes;

  /// 视频时长（秒）。仅 [AssetKind.clip] 有意义；图片为 null。
  ///
  /// 必须有它：合成面板按分镜解析视频文件后要用时长算总时长，缺了这个
  /// 资产片段插进时间线会让总时长算少、进度条走不完（FFmpeg 的 progress
  /// 按实际输入算，跟我们的预估对不上）。
  ///
  /// 入库时由调用方给（它知道刚提交了多久）；本地导入的给不了精确值就
  /// 留 null，让合成侧按默认时长兜底。
  final double? durationSec;

  final DateTime createdAt;

  /// 用户备注（可选）。
  final String? note;

  /// 资产分类。旧数据缺省为 [AssetCategory.other]。
  ///
  /// 加载时回落但不写回：用户没碰过的旧资产不该被悄悄改写索引文件
  /// （design 决策 5）。
  final AssetCategory category;

  /// 自由文本标签。旧数据缺省为空列表。
  final List<String> tags;

  StudioAsset({
    required this.id,
    required this.kind,
    required this.source,
    required this.sizeBytes,
    required this.createdAt,
    this.name,
    this.coverPath,
    this.durationSec,
    this.providerId,
    this.model,
    this.prompt,
    this.sourceCallId,
    this.originPath,
    this.note,
    this.category = AssetCategory.other,
    this.tags = const [],
  });

  /// 资产界面显示名称：若设置了自定义 name 则优先返回，否则回落到 id。
  String get displayName =>
      (name != null && name!.trim().isNotEmpty) ? name!.trim() : id;

  /// 视频海报封面文件对象（仅在本地文件实际存在时返回）。
  File? get coverFile {
    if (coverPath == null || coverPath!.isEmpty) return null;
    final f = File(coverPath!);
    return f.existsSync() ? f : null;
  }

  StudioAsset copyWith({
    String? name,
    String? coverPath,
    String? note,
    AssetCategory? category,
    List<String>? tags,
  }) => StudioAsset(
    id: id,
    kind: kind,
    source: source,
    sizeBytes: sizeBytes,
    durationSec: durationSec,
    createdAt: createdAt,
    providerId: providerId,
    model: model,
    prompt: prompt,
    sourceCallId: sourceCallId,
    originPath: originPath,
    name: name ?? this.name,
    coverPath: coverPath ?? this.coverPath,
    note: note ?? this.note,
    category: category ?? this.category,
    tags: tags ?? this.tags,
  );

  /// 资产文件路径。
  String get path {
    final dir = kind == AssetKind.image
        ? AppPaths.videoStudioAssetImagesDir
        : AppPaths.videoStudioAssetClipsDir;
    return p.join(dir.path, '$id.${kind.extension}');
  }

  File get file => File(path);

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.id,
    'source': source.id,
    if (name != null && name!.isNotEmpty) 'name': name,
    if (coverPath != null && coverPath!.isNotEmpty) 'coverPath': coverPath,
    'providerId': providerId,
    'model': model,
    'prompt': prompt,
    'sourceCallId': sourceCallId,
    'originPath': originPath,
    'sizeBytes': sizeBytes,
    'durationSec': durationSec,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'note': note,
    'category': category.id,
    'tags': tags,
  };

  static StudioAsset? fromJson(Map<String, dynamic> json) {
    try {
      final id = json['id'] as String?;
      final kind = AssetKind.fromId(json['kind'] as String?);
      if (id == null || id.isEmpty || kind == null) return null;
      return StudioAsset(
        id: id,
        kind: kind,
        source: AssetSource.fromId(json['source'] as String?) ?? AssetSource.local,
        name: json['name'] as String?,
        coverPath: json['coverPath'] as String?,
        sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
        durationSec: (json['durationSec'] as num?)?.toDouble(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(
          (json['createdAt'] as num?)?.toInt() ?? 0,
          isUtc: true,
        ),
        providerId: json['providerId'] as String?,
        model: json['model'] as String?,
        prompt: json['prompt'] as String?,
        sourceCallId: json['sourceCallId'] as String?,
        originPath: json['originPath'] as String?,
        note: json['note'] as String?,
        category:
            AssetCategory.fromId(json['category'] as String?) ??
            AssetCategory.other,
        tags: (json['tags'] as List?)?.cast<String>() ?? const [],
      );
    } catch (e) {
      debugPrint('[AssetLibrary] 解析资产条目失败，跳过: $e');
      return null;
    }
  }
}

/// 资产库。
///
/// **为什么是复制不是移动**（design 决策 1）：资产的意义在于它独立于原剧
/// 存在。移动会让"删剧集"变成"删资产"，而用户删一集过时的片子时并不想
/// 连带丢掉一个满意的角色造型。
///
/// **为什么不做跨目录引用**：角色卡的 `referenceImages` 是文件名列表、从
/// 卡片自己的目录读。让卡片直接指向资产库会让剧集对资产库产生隐式依赖，
/// 用户清理资产库时剧集会以"参考图丢失"的怪病形式坏掉。本项目已有
/// `app_paths` 单一性回归测试在防这类事，不该新开一个入口。
///
/// 写盘用「临时文件 + rename」原子写，与 `VideoTaskLedger` /
/// `NovelChapterStorage` 同一套做法：损坏比丢失更糟——丢失至少是空的，
/// 损坏会让启动路径抛异常。
class AssetLibrary {
  AssetLibrary._();
  static final AssetLibrary instance = AssetLibrary._();

  final List<StudioAsset> _assets = <StudioAsset>[];
  final List<StudioAsset> _pending = <StudioAsset>[];
  bool _loaded = false;
  int _lastFileModifiedMs = 0;
  int _localWritesPending = 0;

  final _streamController = StreamController<List<StudioAsset>>.broadcast();

  /// 资产库变更事件广播流（添加、更新、删除、持久化均会触发）。
  Stream<List<StudioAsset>> get stream => _streamController.stream;

  /// 串行化所有写操作。并发写会让 rename 互相覆盖。
  Future<void> _writeChain = Future<void>.value();

  static const _uuid = Uuid();

  /// 当前全部资产（按入库时间倒序——新的在上面）。
  List<StudioAsset> get assets {
    final list = _assets.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List<StudioAsset>.unmodifiable(list);
  }

  /// 尚未落盘的资产（addAsset 已写入内存、后台异步持久化）。
  List<StudioAsset> get pendingAssets =>
      List<StudioAsset>.unmodifiable(_pending);

  /// 从磁盘加载。重复调用只读一次，除非显式 [force: true]。
  ///
  /// 文件不存在 → 空库（正常，首次运行）。
  /// 文件损坏 → 空库 + 日志，**MUST NOT 抛异常**。
  Future<void> ensureLoaded({bool force = false}) async {
    if (_loaded && !force) return;
    if (force && _localWritesPending > 0) {
      await _writeChain;
    }
    await _loadFromDisk();
  }

  /// 检查磁盘索引文件是否被外部进程修改，若修改则自动重载。
  Future<void> _checkExternalDiskUpdate() async {
    if (!_loaded) {
      await ensureLoaded();
      return;
    }
    if (_localWritesPending > 0) return;
    final file = AppPaths.videoStudioAssetIndexFile;
    if (!await file.exists()) return;
    int fileMod = 0;
    try {
      fileMod = (await file.stat()).modified.millisecondsSinceEpoch;
    } catch (_) {}
    if (fileMod > _lastFileModifiedMs) {
      await _loadFromDisk();
    }
  }

  Future<void> _loadFromDisk() async {
    final file = AppPaths.videoStudioAssetIndexFile;
    if (!await file.exists()) {
      _assets.clear();
      _loaded = true;
      _lastFileModifiedMs = 0;
      return;
    }
    int fileMod = 0;
    try {
      fileMod = (await file.stat()).modified.millisecondsSinceEpoch;
    } catch (_) {}

    try {
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is List) {
        _assets.clear();
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            final a = StudioAsset.fromJson(item);
            if (a != null) _assets.add(a);
          } else if (item is Map) {
            final a = StudioAsset.fromJson(item.map((k, v) => MapEntry(k.toString(), v)));
            if (a != null) _assets.add(a);
          }
        }
      }
      _lastFileModifiedMs = fileMod;
    } catch (e) {
      debugPrint('[AssetLibrary] 索引文件损坏，以空库启动: $e');
      _assets.clear();
    }
    _loaded = true;

    // 为尚无封面且原视频存在的 clip 资产异步补充抓取封面帧
    for (final a in _assets) {
      if (a.kind == AssetKind.clip && (a.coverPath == null || a.coverPath!.isEmpty)) {
        _extractCoverFrameAsync(a);
      }
    }
    _streamController.add(assets);
  }

  /// 显式强制从磁盘重载资产索引。
  Future<void> reload() async {
    if (_localWritesPending > 0) {
      await _writeChain;
    }
    await _loadFromDisk();
  }

  Future<void> _persist() {
    _localWritesPending++;
    _writeChain = _writeChain.then((_) async {
      try {
        final file = AppPaths.videoStudioAssetIndexFile;
        final dir = file.parent;
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final tmp = File('${file.path}.tmp');
        await tmp.writeAsString(
          jsonEncode(_assets.map((a) => a.toJson()).toList()),
          flush: true,
        );
        if (await file.exists()) {
          await file.delete();
        }
        await tmp.rename(file.path);
        try {
          _lastFileModifiedMs = (await file.stat()).modified.millisecondsSinceEpoch;
        } catch (_) {}
      } catch (e) {
        debugPrint('[AssetLibrary] 写入失败: $e');
      } finally {
        _localWritesPending--;
        _streamController.add(assets);
      }
    });
    return _writeChain;
  }

  /// 更新资产信息（修改名称、所属分类、备注或封面）。
  Future<StudioAsset?> updateAsset(
    String id, {
    String? name,
    AssetCategory? category,
    String? note,
    String? coverPath,
  }) async {
    await ensureLoaded();
    final idx = _assets.indexWhere((a) => a.id == id);
    if (idx < 0) return null;
    final current = _assets[idx];
    final updated = current.copyWith(
      name: name,
      category: category,
      note: note,
      coverPath: coverPath,
    );
    _assets[idx] = updated;
    await _persist();
    return updated;
  }

  /// 把一个文件收进资产库。**复制，不移动**。
  ///
  /// [sourceCallId] 是产生这个文件的那次调用记录的 localId——传了才能从资产
  /// 反查"我是谁生成的"。
  Future<StudioAsset> addAsset(
    File file, {
    required AssetKind kind,
    String? name,
    File? coverFile,
    AssetSource source = AssetSource.remote,
    String? providerId,
    String? model,
    String? prompt,
    String? sourceCallId,
    String? originPath,
    double? durationSec,
    AssetCategory category = AssetCategory.other,
    List<String> tags = const [],
  }) async {
    await ensureLoaded();
    if (!await file.exists()) {
      throw StateError('要入库的文件不存在: ${file.path}');
    }

    final id = _freshId();

    final dir = kind == AssetKind.image
        ? AppPaths.videoStudioAssetImagesDir
        : AppPaths.videoStudioAssetClipsDir;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }

    String? savedCoverPath;
    if (coverFile != null && await coverFile.exists()) {
      final coverDir = AppPaths.videoStudioAssetImagesDir;
      if (!await coverDir.exists()) {
        await coverDir.create(recursive: true);
      }
      final target = File(p.join(coverDir.path, '${id}_cover.png'));
      final tmp = File('${target.path}.tmp');
      await coverFile.copy(tmp.path);
      await tmp.rename(target.path);
      savedCoverPath = target.path;
    }

    final asset = StudioAsset(
      id: id,
      name: name,
      coverPath: savedCoverPath,
      kind: kind,
      source: source,
      sizeBytes: await file.length(),
      durationSec: durationSec,
      createdAt: DateTime.now().toUtc(),
      providerId: providerId,
      model: model,
      prompt: prompt,
      sourceCallId: sourceCallId,
      originPath: originPath,
      category: category,
      tags: tags,
    );

    // 复制到临时名再 rename：拷到一半被杀不会留下一个看似完整的资产。
    final tmp = File('${asset.path}.tmp');
    await file.copy(tmp.path);
    await tmp.rename(asset.path);

    // 如果是视频片段且没有显式封面图，尝试后台用 FFmpeg 抓取首帧（静默尝试，不阻断入库）
    if (kind == AssetKind.clip && savedCoverPath == null) {
      _extractCoverFrameAsync(asset);
    }

    _assets.add(asset);
    _pending.add(asset);
    await _persist();
    return asset;
  }

  Future<void> _extractCoverFrameAsync(StudioAsset asset) async {
    try {
      final clipFile = asset.file;
      if (!await clipFile.exists()) return;
      final coverDir = AppPaths.videoStudioAssetImagesDir;
      if (!await coverDir.exists()) {
        await coverDir.create(recursive: true);
      }
      final coverTarget = File(p.join(coverDir.path, '${asset.id}_cover.png'));
      if (await coverTarget.exists()) {
        await updateAsset(asset.id, coverPath: coverTarget.path);
        return;
      }
      final ffmpeg = await FfmpegComposer.checkAvailability();
      if (!ffmpeg.available || ffmpeg.path == null) return;
      final res = await Process.run(ffmpeg.path!, [
        '-y',
        '-ss', '00:00:00.500',
        '-i', asset.path,
        '-vframes', '1',
        '-q:v', '2',
        coverTarget.path,
      ]);
      if (res.exitCode == 0 && await coverTarget.exists()) {
        await updateAsset(asset.id, coverPath: coverTarget.path);
      }
    } catch (_) {}
  }

  /// 生成一个不碰撞的 8 位十六进制 ID。
  ///
  /// 8 位空间 43 亿，精选量级下碰撞概率极低；仍做存在性检查，撞了重生成。
  String _freshId() {
    for (var i = 0; i < 8; i++) {
      final candidate = _uuid.v4().replaceAll('-', '').substring(0, 8);
      final exists = _assets.any((a) => a.id == candidate);
      if (!exists) return candidate;
    }
    // 理论上到不了这里。真到了就用时间戳兜底，总比碰撞好。
    return DateTime.now().microsecondsSinceEpoch.toRadixString(16).padLeft(8, '0');
  }

  /// 删除资产（文件 + 索引条目）。
  ///
  /// **不影响已引用它的剧集**——卡片持有的是副本，那是设计使然。
  Future<void> removeAsset(String id) async {
    await ensureLoaded();
    final idx = _assets.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    final asset = _assets[idx];
    try {
      if (await asset.file.exists()) {
        await asset.file.delete();
      }
    } catch (e) {
      debugPrint('[AssetLibrary] 删除资产文件失败: $e');
    }
    _assets.removeAt(idx);
    _pending.removeWhere((a) => a.id == id);
    await _persist();
  }

  /// 按类型列出资产。
  Future<List<StudioAsset>> assetsOf(
    AssetKind kind, {
    AssetCategory? category,
  }) async {
    await _checkExternalDiskUpdate();
    final list = _assets
        .where((a) => a.kind == kind && (category == null || a.category == category))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// 同步取资产——只读已加载进内存的索引。
  ///
  /// 给同步 getter（如 DeliveryPanel 的 `_timelineClips`）用：那些 getter 被
  /// build 与 compose 同步调用，改成 async 会把调用链全拖成异步。调用前需
  /// 已 `ensureLoaded()`；索引未加载时返回 null（此时资产面板还没打开过，
  /// 用户也没可能配置过插入）。
  StudioAsset? assetSync(String id) {
    for (final a in _assets) {
      if (a.id == id) return a;
    }
    return null;
  }

  Future<StudioAsset?> findById(String id) async {
    await _checkExternalDiskUpdate();
    for (final a in _assets) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// 按来源调用记录反查资产（资产 → 调用记录的方向）。
  Future<List<StudioAsset>> assetsFromCall(String sourceCallId) async {
    await _checkExternalDiskUpdate();
    return _assets.where((a) => a.sourceCallId == sourceCallId).toList();
  }

  /// 更新备注。
  Future<void> setNote(String id, String? note) async {
    await ensureLoaded();
    final idx = _assets.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    _assets[idx] = _assets[idx].copyWith(note: note);
    await _persist();
  }

  Future<void> setCategory(String id, AssetCategory category) async {
    await ensureLoaded();
    final idx = _assets.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    _assets[idx] = _assets[idx].copyWith(category: category);
    await _persist();
  }

  Future<void> setTags(String id, List<String> tags) async {
    await ensureLoaded();
    final idx = _assets.indexWhere((a) => a.id == id);
    if (idx < 0) return;
    _assets[idx] = _assets[idx].copyWith(tags: List.unmodifiable(tags));
    await _persist();
  }

  /// 按关键词检索：对提示词与标签做大小写不敏感的包含匹配。
  ///
  /// 两侧都 `toLowerCase()`——否则搜 "agnes" 命中不了 "Agnes"，用户会以为
  /// 检索坏了（design 决策 6）。
  ///
  /// 空关键词返回全部（不去过滤），让调用方少一个分支。
  Future<List<StudioAsset>> search(String keyword) async {
    await _checkExternalDiskUpdate();
    final q = keyword.trim().toLowerCase();
    final list = q.isEmpty
        ? _assets.toList()
        : _assets.where((a) {
            final prompt = a.prompt?.toLowerCase() ?? '';
            final tags = a.tags.map((t) => t.toLowerCase());
            return prompt.contains(q) || tags.any((t) => t.contains(q));
          }).toList();
    return list..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// 清掉 pending 标记（UI 已渲染过）。
  void clearPending() => _pending.clear();

  /// 测试用：清空内存与磁盘状态。
  void resetForTesting() {
    _assets.clear();
    _pending.clear();
    _loaded = false;
    _lastFileModifiedMs = 0;
    _localWritesPending = 0;
  }

  /// 测试用：直接注入条目，跳过文件系统。
  void injectForTesting(StudioAsset asset) {
    _assets.removeWhere((a) => a.id == asset.id);
    _assets.add(asset);
    _loaded = true;
  }
}
