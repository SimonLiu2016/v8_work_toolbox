import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/tools/agnes_playground/models/playground_models.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_task_ledger.dart';

void main() {
  group('PlaygroundDraft & Task Ledger Integration', () {
    late Directory tempDir;
    late File firstFrame;
    late File lastFrame;
    late File refFrame;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('pg_draft_test_');
      firstFrame = File(p.join(tempDir.path, 'first.png'))..writeAsStringSync('f1');
      lastFrame = File(p.join(tempDir.path, 'last.png'))..writeAsStringSync('f2');
      refFrame = File(p.join(tempDir.path, 'ref.png'))..writeAsStringSync('ref');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('fromLedgerEntry 正确还原 aspectRatio、独立首尾帧与 rawPayload', () {
      final entry = VideoTaskLedgerEntry(
        localId: 'task_001',
        providerId: 'agnes_prov',
        adapterId: 'agnes-video',
        model: 'agnes-video-2.5',
        remoteTaskId: 'vid_123',
        status: VideoTaskLedgerStatus.completed,
        seriesId: 's1',
        episodeId: 'e1',
        segmentId: 'seg1',
        shotNumber: 1,
        label: '分镜1',
        targetPath: p.join(tempDir.path, 'out.mp4'),
        prompt: '测试提示词',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        requestSnapshot: {
          'channel': 'video',
          'providerId': 'agnes_prov',
          'model': 'agnes-video-2.5',
          'prompt': '测试提示词',
          'durationSec': 8,
          'durationSeconds': 8,
          'aspectRatio': '9:16',
          'ratio': '9:16',
          'sizeTier': '1080P',
          'resolution': '1080P',
          'mode': 'keyframe',
          'seed': '12345',
          'firstFramePath': firstFrame.path,
          'lastFramePath': lastFrame.path,
          'referencePaths': [refFrame.path],
          'rawPayload': {
            'model': 'agnes-video-2.5',
            'prompt': '测试提示词',
            'mode': 'keyframe',
            'seconds': '8',
            'size': '1080P',
            'aspect_ratio': '9:16',
            'first_frame': '<base64: len=100>',
            'last_frame': '<base64: len=200>',
          },
        },
      );

      final draft = PlaygroundDraft.fromLedgerEntry(entry);

      expect(draft.ratio, '9:16');
      expect(draft.sizeTier, '1080P');
      expect(draft.durationSec, 8);
      expect(draft.mode, 'keyframe');
      expect(draft.seed, '12345');
      expect(draft.prompt, '测试提示词');

      // 验证素材角色正确还原且互不污染
      expect(draft.media.length, 3);
      final first = draft.media.firstWhere((m) => m.role == PlaygroundMediaRole.firstFrame);
      expect(first.file.path, firstFrame.path);
      final last = draft.media.firstWhere((m) => m.role == PlaygroundMediaRole.lastFrame);
      expect(last.file.path, lastFrame.path);
      final ref = draft.media.firstWhere((m) => m.role == PlaygroundMediaRole.reference);
      expect(ref.file.path, refFrame.path);

      // 验证 rawPayload 完整保留并可格式化输出
      expect(draft.rawPayload, isNotNull);
      expect(draft.rawPayload!['aspect_ratio'], '9:16');
      expect(draft.formattedRawPayloadJson, contains('"aspect_ratio": "9:16"'));
      expect(draft.formattedRawPayloadJson, contains('"first_frame": "<base64: len=100>"'));
    });

    test('fromLedgerEntry 兼容老版本快照（无 firstFramePath，但 mode 为 keyframe）', () {
      final entry = VideoTaskLedgerEntry(
        localId: 'task_legacy',
        providerId: 'agnes_prov',
        adapterId: 'agnes-video',
        model: 'agnes-video-2.5-flash',
        remoteTaskId: 'vid_old',
        status: VideoTaskLedgerStatus.completed,
        seriesId: '',
        episodeId: '',
        segmentId: '',
        shotNumber: null,
        label: '老任务',
        targetPath: p.join(tempDir.path, 'out_old.mp4'),
        prompt: '老提示词',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        requestSnapshot: {
          'model': 'agnes-video-2.5-flash',
          'prompt': '老提示词',
          'aspectRatio': '16:9', // 老版本仅写 aspectRatio
          'resolution': '720P', // 老版本仅写 resolution
          'durationSeconds': 6, // 老版本仅写 durationSeconds
          'mode': 'keyframe',
          'referencePaths': [firstFrame.path, lastFrame.path], // 以前把首尾帧全塞进了 referencePaths
        },
      );

      final draft = PlaygroundDraft.fromLedgerEntry(entry);

      // 验证回退键名成功读取
      expect(draft.ratio, '16:9');
      expect(draft.sizeTier, '720P');
      expect(draft.durationSec, 6);
      expect(draft.mode, 'keyframe');

      // 验证老版本数据自动恢复首尾帧角色，杜绝模式互斥拦截
      expect(draft.media.length, 2);
      expect(draft.media[0].role, PlaygroundMediaRole.firstFrame);
      expect(draft.media[0].file.path, firstFrame.path);
      expect(draft.media[1].role, PlaygroundMediaRole.lastFrame);
      expect(draft.media[1].file.path, lastFrame.path);
    });

    test('PlaygroundTurn.renderRedactedJson 格式化生成完整脱敏 JSON', () {
      final turn = PlaygroundTurn(
        id: 'turn_test',
        channel: PlaygroundChannel.video,
        providerId: 'p1',
        providerName: 'Agnes',
        model: 'agnes-video-2.5',
        prompt: '雨中长街',
        params: const {
          'seconds': '5',
          'size': '720P',
          'aspect_ratio': '9:16',
        },
        media: const [
          PlaygroundMedia(
            fileName: 'f1.png',
            originalName: 'first.png',
            role: PlaygroundMediaRole.firstFrame,
            width: 720,
            height: 1280,
            bytes: 50000,
          ),
          PlaygroundMedia(
            fileName: 'ref1.png',
            originalName: 'ref.png',
            role: PlaygroundMediaRole.reference,
            width: 800,
            height: 800,
            bytes: 60000,
          ),
        ],
        status: PlaygroundTurnStatus.completed,
        durationMs: 1200,
        createdAt: DateTime.now(),
      );

      final jsonStr = turn.renderRedactedJson();
      expect(jsonStr, contains('"model": "agnes-video-2.5"'));
      expect(jsonStr, contains('"prompt": "雨中长街"'));
      expect(jsonStr, contains('"aspect_ratio": "9:16"'));
      expect(jsonStr, contains('"first_frame": "<first.png · 720×1280 · 49KB · base64>"'));
      expect(jsonStr, contains('"images": ['));
      expect(jsonStr, contains('<ref.png · 800×800 · 59KB · base64>'));
    });
  });
}
