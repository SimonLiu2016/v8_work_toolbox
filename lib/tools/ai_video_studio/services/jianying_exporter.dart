// 剪映（CapCut Mac 版）草稿导出器。
//
// 剪映的草稿不是开放格式：它把工程存成
// `~/Movies/JianyingPro/User Data/Projects/com.lveditor.draft/<uuid>/draft_content.json`，
// 外加一堆素材文件。结构随版本变化，所以本文件里所有版本相关的字段都集中在
// [draftFormatVersion]，改格式时只动这一处 + 对应 builder。
//
// **这个实现是逆向出来的，不是官方契约。** 因此每次导出前都要做一次自检
// （[validateDraft]）：结构不对就走备用导出（素材文件夹 + 手动导入说明），
// 而不是给用户一个剪映打不开的目录。

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/studio_models.dart';
import 'ffmpeg_composer.dart';
import 'studio_project_manager.dart';
import 'asset_library.dart';

/// 剪映草饺内容格式版本（随剪映版本升级而变）。
///
/// 写进 `draft_content.json` 的 `draft.materials` 之外的顶层字段，剪映自己
/// 靠它判断能否打开。Mac 版 5.x/6.x 实测接受 3。
const int draftFormatVersion = 3;

/// 导出结果。
class JianyingExportResult {
  /// 草稿目录（`exports/jianying_draft/`）。
  final Directory draftDir;

  /// `draft_content.json` 路径。
  final File draftContentFile;

  /// 素材软链接目录。
  final Directory materialsDir;

  const JianyingExportResult({
    required this.draftDir,
    required this.draftContentFile,
    required this.materialsDir,
  });
}

abstract final class JianyingExporter {
  /// 导出一集的剪映草稿。
  ///
  /// 素材用**软链接**而不是复制：剪映读的是路径，软链接让素材仍留在工坊的
  /// `clips/`、`audio/` 目录里（Finder 可直接访问，spec 的目录结构承诺），
  /// 同时剪映那边看到的是完整文件。复制会让一集几十个片段翻倍占盘。
  static Future<JianyingExportResult> export({
    required String outputDir,
    required StudioEpisode episode,
    required List<StudioShot> shots,
    String? srtPath,
    String? bgmPath,
    List<StudioTimelineInsert> timelineInserts = const [],
  }) async {
    final draftDir = Directory(p.join(outputDir, 'jianying_draft'));
    await draftDir.create(recursive: true);
    final materialsDir = Directory(p.join(draftDir.path, 'materials'));
    await materialsDir.create(recursive: true);

    final videoTrack = <Map<String, dynamic>>[];
    final subtitleTrack = <Map<String, dynamic>>[];
    final audioTrack = <Map<String, dynamic>>[];
    final materialRefs = <Map<String, dynamic>>[];

    // --- 视频轨 ------------------------------------------------------------
    //
    // 片段化后一段视频覆盖多个镜头（spec: 片段媒体存放与交付兼容）。剪映的
    // 时间轴按「片段」切比按「镜头」切更自然——一个片段就是时间轴上连续的
    // 一段，用户拖进去就能用。所以这里按片段分组输出，片段内不再拆段。
    var cursorUs = 0; // 微秒
    final segmentById = {
      for (final seg in episode.segments) seg.id: seg,
    };

    // 时间轴上的资产插入，按 afterShotNumber 分組（spec: 视频资产可作为
    // 合成时间线素材）。与 DeliveryPanel._timelineClips 同一套展开规则，
    // 这样合成与剪映导出看到的是同一条时间轴。
    final insertsByShot = <int, List<StudioTimelineInsert>>{};
    for (final ins in timelineInserts) {
      insertsByShot.putIfAbsent(ins.afterShotNumber, () => []).add(ins);
    }

    void appendAssetInserts(int afterShotNumber) {
      final list = insertsByShot.remove(afterShotNumber);
      if (list == null) return;
      for (final ins in list) {
        final asset = AssetLibrary.instance.assetSync(ins.assetId);
        if (asset == null) continue;
        final f = asset.file;
        if (!f.existsSync()) continue;
        // 本地导入的资产可能没有时长信息，按 5 秒兜底——与 DeliveryPanel
        // 的 _timelineDuration 用同一个值，否则两条路径的时长会对不上。
        final durationUs = ((asset.durationSec ?? 5) * 1000000).round();
        final linkName = 'asset_${asset.id}.mp4';
        videoTrack.add({
          'material_id': linkName,
          'start': cursorUs,
          'duration': durationUs,
          'source_start': 0,
          'speed': 1.0,
        });
        materialRefs.add({
          'id': linkName,
          'path': f.path,
          'type': 'asset',
        });
        cursorUs += durationUs;
      }
    }

    // 按分镜顺序走，遇到属于同一片段的连续镜头就合并成一条轨道项。
    final shotStartUs = <int, int>{};
    var i = 0;
    while (i < shots.length) {
      appendAssetInserts(i == 0 ? 0 : shots[i - 1].number);
      final shot = shots[i];
      final segment = shot.segmentId.isEmpty
          ? null
          : segmentById[shot.segmentId];

      // 片段级产物：把该片段中本次要导出的连续镜头合成一条。
      if (segment != null && segment.hasClip) {
        final group = <StudioShot>[];
        while (i < shots.length && shots[i].segmentId == segment.id) {
          // 单独出过片的镜头不并进片段——它有自己的产物。
          if (shots[i].clipPath != null && shots[i].clipPath!.isNotEmpty) break;
          group.add(shots[i]);
          i++;
        }
        if (group.isNotEmpty) {
          final durationUs =
              (segment.targetDurationSec * 1000000).round();
          final linkName = '${segment.id}.mp4';
          videoTrack.add({
            'material_id': linkName,
            'start': cursorUs,
            'duration': durationUs,
            'source_start': 0,
            'speed': 1.0,
          });
          materialRefs.add({
            'id': linkName,
            'path': segment.clipPath!,
            'type': 'segment',
          });
          var offsetUs = 0;
          for (final s in group) {
            shotStartUs[s.number] = cursorUs + offsetUs;
            offsetUs += (s.durationSec * 1000000).round();
          }
          cursorUs += durationUs;
          continue;
        }
      }

      // 分镜级产物：一镜一条，与改造前一致。
      shotStartUs[shot.number] = cursorUs;
      final durationUs = (shot.durationSec * 1000000).round();
      if (shot.clipPath == null || shot.clipPath!.isEmpty) {
        // 没有片段的镜头跳过：剪映轨道上留空洞比插入一段空视频更难排查。
        cursorUs += durationUs;
        i++;
        continue;
      }
      final linkName = 'shot_${shot.number}.mp4';
      videoTrack.add({
        'material_id': linkName,
        'start': cursorUs,
        'duration': durationUs,
        'source_start': 0,
        'speed': 1.0,
      });
      materialRefs.add({
        'id': linkName,
        'path': shot.clipPath!,
        'type': 'video',
      });
      cursorUs += durationUs;
      i++;
    }

    // 收尾：把还没被消费的插入按镜号顺序补齐。它们指向的位置可能是"最后一
    // 镜之后"，也可能是"某个没有视频的镜号"——循环内的 append 经过不了
    // 这些位置，但用户确实配了插入， silently 丢掉比放在末尾更糟。
    final leftovers = insertsByShot.keys.toList()..sort();
    for (final after in leftovers) {
      appendAssetInserts(after);
    }

    // --- 字幕轨（时间码转微秒）---------------------------------------------
    // SRT 的毫秒精度转成剪映的微秒，误差远小于 spec 要求的 50ms。
    if (srtPath != null && File(srtPath).existsSync()) {
      final entries = FfmpegComposer.parseSrt(File(srtPath).readAsStringSync());
      for (final entry in entries) {
        subtitleTrack.add({
          'start': (entry.start * 1000000).round(),
          'duration': ((entry.end - entry.start) * 1000000).round(),
          'text': entry.text,
        });
      }
    }

    // --- 台词音频轨 --------------------------------------------------------
    for (final shot in shots) {
      if (shot.audioPath == null || shot.audioPath!.isEmpty) continue;
      final startUs = shotStartUs[shot.number] ?? 0;
      audioTrack.add({
        'material_id': 'audio_${shot.number}',
        'start': startUs,
        'duration':
            (shot.audioDurationMs ?? 0) * 1000, // 毫秒 → 微秒
        'text': shot.dialogue,
      });
    }

    final draft = <String, dynamic>{
      'version': draftFormatVersion,
      'canvas': {'width': 1080, 'height': 1920, 'ratio': '9:16'},
      'tracks': [
        {'type': 'video', 'segments': videoTrack},
        {'type': 'audio', 'segments': audioTrack},
        {'type': 'text', 'segments': subtitleTrack},
        if (bgmPath != null && File(bgmPath).existsSync())
          {
            'type': 'bgm',
            'segments': [
              {
                'material_id': 'bgm',
                'start': 0,
                'duration': cursorUs,
                // 剪映侧 Ducking 用的是「自动避让人声」开关，不是时间区间表。
                'ducking': true,
              },
            ],
            'material': {'id': 'bgm', 'path': bgmPath, 'type': 'audio'},
          },
      ],
      'materials': materialRefs,
    };

    final draftFile = File(p.join(draftDir.path, 'draft_content.json'));
    await draftFile.writeAsString(
      const JsonEncoder.withIndent('  ').convert(draft),
      flush: true,
    );

    // --- 素材软链接 --------------------------------------------------------
    await _linkMaterials(materialsDir, materialRefs, episode);

    final result = JianyingExportResult(
      draftDir: draftDir,
      draftContentFile: draftFile,
      materialsDir: materialsDir,
    );

    // 自检：结构不对立刻改走备用导出，别让用户拿到打不开的目录。
    final problems = validateDraft(result);
    if (problems.isNotEmpty) {
      throw StateError(
        '剪映草稿结构自检未通过：${problems.join('；')}',
      );
    }
    return result;
  }

  /// 自检：返回问题列表，空数组表示通过。
  static List<String> validateDraft(JianyingExportResult result) {
    final problems = <String>[];
    if (!result.draftDir.existsSync()) {
      problems.add('草稿目录不存在');
      return problems;
    }
    final file = result.draftContentFile;
    if (!file.existsSync()) {
      problems.add('缺少 draft_content.json');
      return problems;
    }
    try {
      final decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) {
        problems.add('draft_content.json 不是 JSON 对象');
        return problems;
      }
      final json = decoded.map((k, v) => MapEntry(k as String, v));
      if (json['version'] != draftFormatVersion) {
        problems.add('版本字段缺失或不匹配');
      }
      final tracks = json['tracks'];
      if (tracks is! List || tracks.isEmpty) {
        problems.add('没有轨道');
      } else {
        for (final t in tracks) {
          if (t is! Map || t['type'] is! String) {
            problems.add('轨道缺少 type 字段');
            break;
          }
        }
      }
    } catch (e) {
      problems.add('draft_content.json 解析失败: $e');
    }
    return problems;
  }

  /// 备用导出：素材平铺目录 + 手动导入说明。
  ///
  /// 剪映格式随版本会变，这就是那条退路（design.md Risks）。复制而不是软
  /// 链接：用户要把整个文件夹拖到别的机器上，软链接会全断。
  static Future<Directory> exportFallback({
    required String outputDir,
    required StudioEpisode episode,
    required List<StudioShot> shots,
    String? srtPath,
    String? bgmPath,
  }) async {
    final fallback = Directory(p.join(outputDir, 'jianying_fallback'));
    await fallback.create(recursive: true);
    for (final sub in ['video', 'audio', 'subtitles']) {
      await Directory(p.join(fallback.path, sub)).create(recursive: true);
    }

    // 片段产物也拷进去：兜底目录是给用户手动拖素材用的，少一个片段就等于
    // 少一段成片，用户不会意识到是"片段视频没导出来"。
    final segmentById = {for (final seg in episode.segments) seg.id: seg};
    final copiedSegments = <String>{};
    for (final shot in shots) {
      if (shot.clipPath != null && shot.clipPath!.isNotEmpty) {
        await _copyIfExists(
          File(p.join(episodeClipsDirOf(episode), shot.clipPath!)),
          File(p.join(fallback.path, 'video', 'shot_${shot.number}.mp4')),
        );
      } else if (shot.segmentId.isNotEmpty) {
        final segment = segmentById[shot.segmentId];
        if (segment != null &&
            segment.hasClip &&
            copiedSegments.add(segment.id)) {
          await _copyIfExists(
            File(p.join(episodeSegmentsDirOf(episode), segment.clipPath!)),
            File(p.join(fallback.path, 'video', '${segment.id}.mp4')),
          );
        }
      }
      if (shot.audioPath != null && shot.audioPath!.isNotEmpty) {
        await _copyIfExists(
          File(p.join(episodeAudioDirOf(episode), shot.audioPath!)),
          File(p.join(fallback.path, 'audio', 'shot_${shot.number}.m4a')),
        );
      }
    }
    if (srtPath != null) {
      await _copyIfExists(
        File(srtPath),
        File(p.join(fallback.path, 'subtitles', p.basename(srtPath))),
      );
    }
    if (bgmPath != null) {
      await _copyIfExists(File(bgmPath), File(p.join(fallback.path, 'audio', 'bgm.mp3')));
    }

    final readme = File(p.join(fallback.path, '导入说明.txt'));
    await readme.writeAsString(
      '剪映草稿导出自检未通过，已改为素材文件夹导出。\n\n'
      '手动导入步骤：\n'
      '1. 打开剪映，新建一个 9:16 竖屏工程。\n'
      '2. 把 video/ 里的片段按文件名序号拖到时间轴（文件名即分镜顺序）。\n'
      '3. 把 audio/ 里的台词音频与 bgm 拖到音频轨。\n'
      '4. 用「文本 → 本地字幕」导入 subtitles/ 里的 SRT 文件。\n',
      flush: true,
    );
    return fallback;
  }

  static Future<void> _linkMaterials(
    Directory materialsDir,
    List<Map<String, dynamic>> refs,
    StudioEpisode episode,
  ) async {
    for (final ref in refs) {
      final id = ref['id'] as String;
      final type = ref['type'] as String;
      // 'asset' 的 path 是资产库里的**绝对路径**——资产在剧集目录之外，
      // 不能按 episode 的子目录拼。所以它必须是独立分支而不是 default。
      final source = switch (type) {
        'video' => File(p.join(episodeClipsDirOf(episode), ref['path'] as String)),
        'segment' => File(
          p.join(episodeSegmentsDirOf(episode), ref['path'] as String),
        ),
        'asset' => File(ref['path'] as String),
        _ => File(p.join(episodeAudioDirOf(episode), ref['path'] as String)),
      };
      final link = Link(p.join(materialsDir.path, id));
      try {
        if (await link.exists()) await link.delete();
        // 源文件不存在时不要建一个断链：草稿里躺着打不开的素材，
        // 用户只会以为剪映坏了。
        if (!await source.exists()) continue;
        await link.create(source.absolute.path);
      } catch (_) {
        // 软链接失败（跨卷/权限）时退回复制：占盘换可用。
        if (await source.exists()) {
          await source.copy(link.path);
        }
      }
    }
  }

  static Future<void> _copyIfExists(File from, File to) async {
    if (!await from.exists()) return;
    await to.parent.create(recursive: true);
    await from.copy(to.path);
  }

  /// 单集的素材目录。走数据层而不是自己拼：`storyboard.json` 存的是相对
  /// 路径，绝对目录由 [StudioProjectManager] 一处决定。
  static String episodeClipsDirOf(StudioEpisode e) =>
      StudioProjectManager.instance
          .episodeClipsDir(e.seriesId, e.id)
          .path;

  /// 片段级视频目录。与 `clips/` 分开：一个放分镜产物，一个放片段产物。
  static String episodeSegmentsDirOf(StudioEpisode e) =>
      StudioProjectManager.instance
          .episodeSegmentsDir(e.seriesId, e.id)
          .path;

  static String episodeAudioDirOf(StudioEpisode e) =>
      StudioProjectManager.instance
          .episodeAudioDir(e.seriesId, e.id)
          .path;
}
