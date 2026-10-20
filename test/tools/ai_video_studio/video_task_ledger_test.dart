import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/media_capability.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_task_ledger.dart';

/// 云端视频任务台账的持久化与状态机回归。
///
/// 这个文件守的是「积分扣了却不能丢线索」这条性质：视频任务创建即计费，
/// 台账是用户唯一能证明「钱花了、视频在哪」的东西。所以每一条断言都在验
/// 「某种中断之后线索还在不在」，而不是在验 JSON 序列化本身。
void main() {
  group('VideoTaskLedger 持久化', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('ledger_test');
      AppPaths.overrideRootForTesting(tempDir);
      VideoTaskLedger.instance.resetForTesting();
    });

    tearDown(() {
      VideoTaskLedger.instance.resetForTesting();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Future<VideoTaskLedgerEntry> seed({String? remoteTaskId}) =>
        VideoTaskLedger.instance.record(
          providerId: 'p1',
          adapterId: 'agnes-video-2.5-flash',
          model: 'agnes-video-2.5-flash',
          remoteTaskId: remoteTaskId ?? 'video_abc123',
          seriesId: 's1',
          episodeId: 'e1',
          segmentId: 'seg1',
          shotNumber: null,
          label: '片段视频 seg1',
          targetPath: p.join(tempDir.path, 'seg1.mp4'),
        );

    test('创建即落盘——轮询开始前文件已存在', () async {
      await seed();
      expect(
        AppPaths.videoTaskLedgerFile.existsSync(),
        isTrue,
        reason: '台账必须在轮询开始前落盘，否则轮询途中被杀就无线索',
      );
    });

    test('落盘内容是 JSON 数组且含 video_id', () async {
      await seed();
      final text = await AppPaths.videoTaskLedgerFile.readAsString();
      expect(text.contains('video_abc123'), isTrue);
      expect(text.contains('agnes-video-2.5-flash'), isTrue);
    });

    test('重启后读回——新实例视角下条目与状态都在', () async {
      await seed();
      // 模拟进程重启：清内存但不动磁盘。
      VideoTaskLedger.instance.resetForTesting();
      final pending = await VideoTaskLedger.instance.pendingEntries();
      expect(pending, hasLength(1));
      expect(pending.first.remoteTaskId, 'video_abc123');
      expect(pending.first.status, VideoTaskLedgerStatus.polling);
      expect(pending.first.segmentId, 'seg1');
      expect(pending.first.targetPath, endsWith('seg1.mp4'));
    });

    test('状态跃迁跨重启保留', () async {
      await seed();
      await VideoTaskLedger.instance.update(
        'agnes-video-2.5-flash_video_abc123',
        status: VideoTaskLedgerStatus.cloudProcessing,
        lastRemoteStatus: 'queued',
        lastProgress: 30,
        sawInProgress: false,
      );
      VideoTaskLedger.instance.resetForTesting();

      final entry = await VideoTaskLedger.instance
          .findByRemoteId('video_abc123');
      expect(entry, isNotNull);
      expect(entry!.status, VideoTaskLedgerStatus.cloudProcessing);
      expect(entry.lastProgress, 30);
      expect(entry.sawInProgress, isFalse);
    });

    test('同一 remoteTaskId 不重复登记', () async {
      await seed();
      await seed(); // 同 id 再来一次
      final all = await VideoTaskLedger.instance.allEntries();
      expect(all, hasLength(1));
    });

    test('并发写入不损坏文件', () async {
      // 20 个任务同时登记。串行化若失效，rename 会互相覆盖，最终读回的
      // 条目数会少于 20。
      final futures = <Future<void>>[];
      for (var i = 0; i < 20; i++) {
        futures.add(
          VideoTaskLedger.instance.record(
            providerId: 'p1',
            adapterId: 'agnes-video-2.5-flash',
            model: 'agnes-video-2.5-flash',
            remoteTaskId: 'video_$i',
            seriesId: 's1',
            episodeId: 'e1',
            segmentId: 'seg$i',
            shotNumber: null,
            label: '片段 $i',
            targetPath: p.join(tempDir.path, 'seg$i.mp4'),
          ),
        );
      }
      await Future.wait(futures);
      VideoTaskLedger.instance.resetForTesting();
      final all = await VideoTaskLedger.instance.allEntries();
      expect(all, hasLength(20));
    });

    test('损坏文件降级为空台账，不抛异常', () async {
      await seed();
      // 直接写垃圾进去，绕过原子写。
      await AppPaths.videoTaskLedgerFile.writeAsString('{ not json at all');
      VideoTaskLedger.instance.resetForTesting();

      // 这一行是重点：启动路径不能被坏数据文件阻断。
      final all = await VideoTaskLedger.instance.allEntries();
      expect(all, isEmpty);

      // 降级后仍可正常写入——不是一次性瘫痪。
      await seed(remoteTaskId: 'video_after_corruption');
      final after = await VideoTaskLedger.instance.allEntries();
      expect(after, hasLength(1));
    });

    test('缺 localId 的条目被跳过，空 remoteTaskId 的照常读回', () async {
      // 这条守的是一个真实 bug：fromJson 曾判 remoteTaskId 非空，于是所有
      // 图片调用记录（remoteTaskId 为空串）落盘后重新加载时全被丢弃——
      // 写进去了，读不出来。必需字段是 localId，不是 remoteTaskId。
      await AppPaths.videoTaskLedgerDir.create(recursive: true);
      await AppPaths.videoTaskLedgerFile.writeAsString(
        '[{"model":"m"},{"localId":"y","remoteTaskId":"v1"},'
          '{"localId":"z","remoteTaskId":""}]',
      );
      VideoTaskLedger.instance.resetForTesting();
      final all = await VideoTaskLedger.instance.allEntries();
      expect(all, hasLength(2), reason: '缺 localId 的才该被跳过');
      expect(all.map((e) => e.localId), containsAll(['y', 'z']));
      expect(all.firstWhere((e) => e.localId == 'z').remoteTaskId, isEmpty);
    });

    test('pendingEntries 只返回 active 状态', () async {
      await seed();
      await VideoTaskLedger.instance.update(
        'agnes-video-2.5-flash_video_abc123',
        status: VideoTaskLedgerStatus.completed,
      );
      final pending = await VideoTaskLedger.instance.pendingEntries();
      expect(pending, isEmpty);
      final all = await VideoTaskLedger.instance.allEntries();
      expect(all, hasLength(1));
    });

    test('多条图片调用（空 remoteTaskId）互不覆盖', () async {
      // 曾经的坑：去重键用 remoteTaskId，空串让所有图片调用互判重复，
      // 只留得下最后一条。现在键是 localId。
      for (var i = 0; i < 5; i++) {
        await VideoTaskLedger.instance.record(
          providerId: 'agnes',
          adapterId: 'image-adapter',
          model: 'agnes-image-2.5-flash',
          remoteTaskId: '', // 同步接口没有任务 ID
          seriesId: 's1',
          episodeId: 'e1',
          segmentId: '',
          shotNumber: i,
          label: '分镜 $i 关键帧',
          targetPath: p.join(tempDir.path, 'shot_$i.png'),
          localId: 'img_call_$i',
          prompt: '提示词 $i',
        );
      }
      final all = await VideoTaskLedger.instance.allEntries();
      expect(all, hasLength(5), reason: '五条图片调用都该留下');
      expect(all.where((e) => e.remoteTaskId.isEmpty), hasLength(5));
      expect(all.first.prompt, isNotEmpty, reason: '提示词要能回望');
    });

    test('prune 永不清理已完成条目（云端 URL 长期有效）', () async {
      await seed();
      await VideoTaskLedger.instance.update(
        'agnes-video-2.5-flash_video_abc123',
        status: VideoTaskLedgerStatus.completed,
      );
      await VideoTaskLedger.instance.backdateForTesting(
        'agnes-video-2.5-flash_video_abc123',
        const Duration(days: 365),
      );

      // 普通 prune 不管过多老都不该碰 completed。
      expect(await VideoTaskLedger.instance.prune(const Duration(days: 1)), 0);
      final all = await VideoTaskLedger.instance.allEntries();
      expect(all, hasLength(1), reason: '已完成任务永久保留——它的云端 URL 还能取回');

      // 显式动作用另一个方法。
      expect(
        await VideoTaskLedger.instance.pruneCompleted(const Duration(days: 30)),
        1,
      );
    });

    test('update 传 null 的字段保持原值', () async {
      await seed();
      await VideoTaskLedger.instance.update(
        'agnes-video-2.5-flash_video_abc123',
        lastRemoteStatus: 'in_progress',
        lastProgress: 42,
        sawInProgress: true,
      );
      // 只改 status，其余字段应保持。
      await VideoTaskLedger.instance.update(
        'agnes-video-2.5-flash_video_abc123',
        status: VideoTaskLedgerStatus.cloudProcessing,
      );
      final e = await VideoTaskLedger.instance
          .findByLocalId('agnes-video-2.5-flash_video_abc123');
      expect(e!.status, VideoTaskLedgerStatus.cloudProcessing);
      expect(e.lastRemoteStatus, 'in_progress', reason: '未传的字段不该被清空');
      expect(e.lastProgress, 42);
      expect(e.sawInProgress, isTrue,
          reason: 'refreshStatusOnce 靠传 null 表示"不改这个字段"');
    });

    test('prompt 持久化并可回望', () async {
      await VideoTaskLedger.instance.record(
        providerId: 'agnes',
        adapterId: 'image-adapter',
        model: 'agnes-image-2.5-flash',
        remoteTaskId: '',
        seriesId: 's1',
        episodeId: 'e1',
        segmentId: '',
        shotNumber: 3,
        label: '分镜 3 关键帧',
        targetPath: p.join(tempDir.path, 'shot_3.png'),
        localId: 'img_p1',
        prompt: '雨夜天台，少女回眸',
      );
      VideoTaskLedger.instance.resetForTesting();
      final e = await VideoTaskLedger.instance.findByLocalId('img_p1');
      expect(e, isNotNull);
      expect(e!.prompt, '雨夜天台，少女回眸');
      expect(e.remoteTaskId, isEmpty);
    });

    test('prune 只清理已终结条目，active 的一个都不碰', () async {
      await seed(); // polling
      await VideoTaskLedger.instance.record(
        providerId: 'p1',
        adapterId: 'agnes-video-2.5-flash',
        model: 'agnes-video-2.5-flash',
        remoteTaskId: 'video_done',
        seriesId: 's1',
        episodeId: 'e1',
        segmentId: 'seg2',
        shotNumber: null,
        label: '片段 2',
        targetPath: p.join(tempDir.path, 'seg2.mp4'),
      );
      await VideoTaskLedger.instance.update(
        'agnes-video-2.5-flash_video_done',
        status: VideoTaskLedgerStatus.completed,
      );
      // 刚完成的条目在窗口内，不该被清掉——把时钟往前拨一周才越过窗口。
      expect(
        await VideoTaskLedger.instance.prune(const Duration(days: 7)),
        0,
        reason: '刚完成的条目还在保留窗口内',
      );

      await VideoTaskLedger.instance.backdateForTesting(
        'agnes-video-2.5-flash_video_done',
        const Duration(days: 8),
      );
      // 已完成任务改用显式方法清理——普通 prune 永久保留它。
      final removed = await VideoTaskLedger.instance
          .pruneCompleted(const Duration(days: 7));
      expect(removed, 1, reason: '只应清掉 completed 那个');
      final all = await VideoTaskLedger.instance.allEntries();
      expect(all, hasLength(1));
      expect(all.first.remoteTaskId, 'video_abc123');
    });

    test('remove 删除指定条目', () async {
      await seed();
      await VideoTaskLedger.instance
          .remove('agnes-video-2.5-flash_video_abc123');
      final all = await VideoTaskLedger.instance.allEntries();
      expect(all, isEmpty);
    });

    test('台账目录已登记进 allDirs 且在 root 之下', () {
      expect(
        AppPaths.allDirs.any((d) => d.path == AppPaths.videoTaskLedgerDir.path),
        isTrue,
        reason: '未登记的目录会在路径单一性回归里变成漏网的硬编码路径',
      );
    });
  });

  group('Agnes 能力声明分档', () {
    test('flash 视频型号分辨率恰为 720P 一档', () {
      final cap = MediaCapabilityPresets.forModel('agnes-video-2.5-flash');
      expect(cap, isNotNull);
      expect(cap!.resolutions, ['720p']);
      expect(cap.supportsFirstFrame, isTrue);
      expect(cap.maxReferenceImages, 5);
    });

    test('标准视频型号支持四档分辨率与尾帧', () {
      final cap = MediaCapabilityPresets.forModel('agnes-video-2.5');
      expect(cap, isNotNull);
      expect(cap!.resolutions, ['720p', '1080p', '1k', '2k']);
      expect(cap.supportsLastFrame, isTrue);
      expect(cap.maxReferenceImages, 8);
    });

    test('图像型号不继承视频能力', () {
      // 曾经的 bug：agnes-image-2.5-flash 命中视频声明，图像模型因此拿到
      // 视频的时长与模式约束。这条断言守那个修复不回退。
      for (final id in const [
        'agnes-image-2.0-flash',
        'agnes-image-2.1-flash',
        'agnes-image-2.5-flash',
      ]) {
        final cap = MediaCapabilityPresets.forModel(id);
        expect(cap, isNotNull, reason: id);
        expect(cap!.durations, isEmpty, reason: '$id 不该有时长维度');
        expect(cap.resolutions, ['1k', '2k', '3k', '4k'], reason: id);
        expect(cap.ratios, contains('9:16'), reason: id);
        expect(cap.supportsFirstFrame, isFalse, reason: id);
      }
    });

    test('flash 与标准型号的能力声明不是同一个对象', () {
      final flash = MediaCapabilityPresets.forModel('agnes-video-2.5-flash');
      final std = MediaCapabilityPresets.forModel('agnes-video-2.5');
      expect(identical(flash, std), isFalse);
      expect(flash!.resolutions, isNot(std!.resolutions));
    });

    test('未知 agnes 型号返回 null，不误命中', () {
      expect(MediaCapabilityPresets.forModel('agnes-video-9.9'), isNull);
    });
  });
}
