import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/privacy_security_service.dart';
import 'package:V8WorkToolbox/tools/private_player/services/ai_subtitle_service.dart';
import 'package:V8WorkToolbox/tools/private_player/services/download_queue_manager.dart';
import 'package:V8WorkToolbox/tools/private_player/services/media_history_store.dart';
import 'package:V8WorkToolbox/tools/private_player/services/private_player_controller.dart';
import 'package:V8WorkToolbox/tools/private_player/services/private_storage_manager.dart';
import 'package:V8WorkToolbox/tools/private_player/services/thumbnail_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PrivacySecurityService PIN Tests', () {
    test('hashPin produces deterministic SHA-256 hash with salt', () {
      const pin = '123456';
      const salt = 'random_salt_123';

      final hash1 = PrivacySecurityService.hashPin(pin, salt);
      final hash2 = PrivacySecurityService.hashPin(pin, salt);
      expect(hash1, equals(hash2));
      expect(hash1.length, equals(64)); // SHA-256 hex is 64 chars

      // Different pin or salt produces different hash
      final hashDifferentPin = PrivacySecurityService.hashPin('654321', salt);
      final hashDifferentSalt = PrivacySecurityService.hashPin(pin, 'another_salt');
      expect(hash1, isNot(equals(hashDifferentPin)));
      expect(hash1, isNot(equals(hashDifferentSalt)));
    });

    test('isUnlockedNotifier toggles correctly with lock()', () {
      final service = PrivacySecurityService.instance;
      service.isUnlockedNotifier.value = true;
      expect(service.isUnlocked, isTrue);

      service.lock();
      expect(service.isUnlocked, isFalse);
    });

    test('PlaybackInhibitor inhibits auto-lock and resumes after stopping', () {
      final service = PrivacySecurityService.instance;
      service.isUnlockedNotifier.value = true;
      service.recordActivity();

      bool isPlaying = true;
      bool inhibitor() => isPlaying;

      service.registerPlaybackInhibitor(inhibitor);
      expect(service.isPlaybackActive(), isTrue);

      // 播放中：即使超过 10 分钟闲置，也应完全抑制锁定
      final tenMinutesLater = DateTime.now().add(const Duration(minutes: 10));
      final lockedDuringPlay = service.checkIdleTimeout(currentTime: tenMinutesLater);
      expect(lockedDuringPlay, isFalse);
      expect(service.isUnlocked, isTrue);

      // 停止播放：此时经过 6 分钟应当正常触发闲置自动锁定
      isPlaying = false;
      expect(service.isPlaybackActive(), isFalse);

      final sixMinutesAfterStop = DateTime.now().add(const Duration(minutes: 6));
      final lockedAfterStop = service.checkIdleTimeout(currentTime: sixMinutesAfterStop);
      expect(lockedAfterStop, isTrue);
      expect(service.isUnlocked, isFalse);

      service.unregisterPlaybackInhibitor(inhibitor);
    });
  });

  group('AiSubtitleService SRT Export Tests', () {
    test('exportAsSrt formats segments into valid SRT format', () {
      final segments = [
        SubtitleSegment(
          id: 1,
          start: const Duration(seconds: 1, milliseconds: 500),
          end: const Duration(seconds: 4, milliseconds: 200),
          text: 'Hello world, this is a subtitle.',
        ),
        SubtitleSegment(
          id: 2,
          start: const Duration(minutes: 1, seconds: 10),
          end: const Duration(minutes: 1, seconds: 15, milliseconds: 750),
          text: 'Second line of dialog.',
        ),
      ];

      final srt = AiSubtitleService.exportAsSrt(segments);

      expect(srt, contains('1\n00:00:01,500 --> 00:00:04,200\nHello world, this is a subtitle.'));
      expect(srt, contains('2\n00:01:10,000 --> 00:01:15,750\nSecond line of dialog.'));
    });

    test('parseSrtOrVtt correctly parses SRT and WebVTT formats', () {
      const srtSample = '''
1
00:00:01,234 --> 00:00:03,456
First line of subtitle

2
00:01:10,000 --> 00:01:15,500
Second line of subtitle
with second row
''';

      final srtSegs = AiSubtitleService.parseSrtOrVtt(srtSample);
      expect(srtSegs.length, equals(2));
      expect(srtSegs[0].start, equals(const Duration(seconds: 1, milliseconds: 234)));
      expect(srtSegs[0].end, equals(const Duration(seconds: 3, milliseconds: 456)));
      expect(srtSegs[0].text, equals('First line of subtitle'));
      expect(srtSegs[1].start, equals(const Duration(minutes: 1, seconds: 10)));
      expect(srtSegs[1].text, equals('Second line of subtitle\nwith second row'));

      const vttSample = '''
WEBVTT

00:00:05.100 --> 00:00:08.200
<v Speaker>Hello from WebVTT!</v>
''';

      final vttSegs = AiSubtitleService.parseSrtOrVtt(vttSample);
      expect(vttSegs.length, equals(1));
      expect(vttSegs[0].start, equals(const Duration(seconds: 5, milliseconds: 100)));
      expect(vttSegs[0].end, equals(const Duration(seconds: 8, milliseconds: 200)));
      expect(vttSegs[0].text, equals('Hello from WebVTT!'));
    });
  });

  group('MediaHistoryStore & Records Tests', () {
    test('MediaPlayRecord serialization and deserialization', () {
      final record = MediaPlayRecord(
        id: 'test_id',
        urlOrPath: '/path/to/private/video.mp4',
        title: 'Secret Video',
        isOnline: false,
        durationMs: const Duration(minutes: 20).inMilliseconds,
        lastPositionMs: const Duration(minutes: 5, seconds: 23).inMilliseconds,
        lastPlayedAt: DateTime(2026, 9, 7, 23, 0),
        thumbnailUrl: 'thumb.jpg',
      );

      final json = record.toJson();
      expect(json['urlOrPath'], equals('/path/to/private/video.mp4'));
      expect(json['title'], equals('Secret Video'));
      expect(json['lastPositionMs'], equals(const Duration(minutes: 5, seconds: 23).inMilliseconds));

      final fromJson = MediaPlayRecord.fromJson(json);
      expect(fromJson.urlOrPath, equals(record.urlOrPath));
      expect(fromJson.title, equals(record.title));
      expect(fromJson.lastPosition, equals(record.lastPosition));
      expect(fromJson.duration, equals(record.duration));
    });

    test('MediaHistoryStore in-memory updates', () async {
      final tempDir = Directory.systemTemp.createTempSync('history_test');
      try {
        await PrivateStorageManager.instance.init(customRoot: tempDir);
        await MediaHistoryStore.instance.init();
        await MediaHistoryStore.instance.clearHistory();

        await MediaHistoryStore.instance.recordPlayback(
          urlOrPath: '/test/movie.mp4',
          title: 'Movie 1',
          position: const Duration(seconds: 120),
          duration: const Duration(minutes: 90),
        );

        expect(MediaHistoryStore.instance.history.length, equals(1));
        expect(MediaHistoryStore.instance.history.first.title, equals('Movie 1'));

        final resumePos = MediaHistoryStore.instance.getLastPosition('/test/movie.mp4');
        expect(resumePos, equals(const Duration(seconds: 120)));

        // Favorites toggle
        expect(MediaHistoryStore.instance.isFavorite('/test/movie.mp4'), isFalse);
        await MediaHistoryStore.instance.toggleFavorite(urlOrPath: '/test/movie.mp4', title: 'Movie 1');
        expect(MediaHistoryStore.instance.isFavorite('/test/movie.mp4'), isTrue);
        await MediaHistoryStore.instance.toggleFavorite(urlOrPath: '/test/movie.mp4', title: 'Movie 1');
        expect(MediaHistoryStore.instance.isFavorite('/test/movie.mp4'), isFalse);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });
  });

  group('DownloadQueueManager Tests', () {
    test('DownloadTask updates progress and status correctly', () {
      final task = DownloadTask(
        id: 'task_1',
        url: 'https://www.bilibili.com/video/BV123456',
        title: 'Bilibili Test',
      );

      expect(task.status, equals(DownloadStatus.queued));
      expect(task.progress, equals(0.0));

      task.update(
        newProgress: 0.45,
        newSpeed: '2.5MiB/s',
        newEta: '00:30',
        newStatus: DownloadStatus.downloading,
      );

      expect(task.status, equals(DownloadStatus.downloading));
      expect(task.progress, equals(0.45));
      expect(task.speed, equals('2.5MiB/s'));
      expect(task.eta, equals('00:30'));
    });

    test('DownloadQueueManager adds tasks and avoids duplicates', () {
      final queue = DownloadQueueManager.instance;
      queue.clearAll();

      final t1 = queue.addTask('https://youtube.com/watch?v=111');
      expect(queue.tasks.length, equals(1));
      expect(t1.url, equals('https://youtube.com/watch?v=111'));

      // Adding same URL returns existing task
      final t2 = queue.addTask('https://youtube.com/watch?v=111');
      expect(queue.tasks.length, equals(1));
      expect(t2.id, equals(t1.id));

      // Batch add
      queue.addBatch([
        'https://youtube.com/watch?v=222',
        'https://youtube.com/watch?v=333',
      ]);
      expect(queue.tasks.length, equals(3));
      queue.clearAll();
    });
  });

  group('Xiaomi MiMo ASR Tests', () {
    test('isMimoProvider accurately recognizes MiMo models and baseUrls', () {
      final mimoConfig = const AiProviderConfig(
        id: 'p_mimo',
        name: 'Xiaomi MiMo',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://token-plan-sgp.xiaomimimo.com',
        keychainKeyId: 'k1',
      );

      final openAiConfig = const AiProviderConfig(
        id: 'p_openai',
        name: 'OpenAI',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://api.openai.com',
        keychainKeyId: 'k2',
      );

      expect(AiSubtitleService.isMimoProvider(mimoConfig, 'mimo-v2.5-asr'), isTrue);
      expect(AiSubtitleService.isMimoProvider(mimoConfig, 'whisper-1'), isTrue); // baseUrl matches
      expect(AiSubtitleService.isMimoProvider(openAiConfig, 'mimo-v2.5-asr'), isTrue); // model matches
      expect(AiSubtitleService.isMimoProvider(openAiConfig, 'whisper-1'), isFalse);
    });

    test('isSilenceOrFiller filters out non-speech sounds and fillers', () {
      expect(AiSubtitleService.isSilenceOrFiller(''), isTrue);
      expect(AiSubtitleService.isSilenceOrFiller('   '), isTrue);
      expect(AiSubtitleService.isSilenceOrFiller('嗯。'), isTrue);
      expect(AiSubtitleService.isSilenceOrFiller('啊！'), isTrue);
      expect(AiSubtitleService.isSilenceOrFiller('哦……'), isTrue);
      expect(AiSubtitleService.isSilenceOrFiller('静音'), isTrue);
      expect(AiSubtitleService.isSilenceOrFiller('...'), isTrue);

      // Real subtitle text should NOT be filtered
      expect(AiSubtitleService.isSilenceOrFiller('欢迎观看本期视频'), isFalse);
      expect(AiSubtitleService.isSilenceOrFiller('Hello World'), isFalse);
      expect(AiSubtitleService.isSilenceOrFiller('嗯，这是非常重要的概念'), isFalse);
    });
  });

  group('ThumbnailManager & Directory Tests', () {
    test('getThumbnailFileName produces deterministic hash filename', () {
      const url1 = 'https://example.com/video.mp4';
      const url2 = 'https://example.com/video.mp4';
      const path1 = '/Users/test/private/my_video.mkv';

      final fn1 = ThumbnailManager.getThumbnailFileName(url1);
      final fn2 = ThumbnailManager.getThumbnailFileName(url2);
      final fn3 = ThumbnailManager.getThumbnailFileName(path1);

      expect(fn1, equals(fn2));
      expect(fn1.startsWith('thumb_'), isTrue);
      expect(fn1.endsWith('.jpg'), isTrue);
      expect(fn1, isNot(equals(fn3)));
    });

    test('buildFfmpegArgs builds valid screenshot extraction arguments', () {
      final args = ThumbnailManager.buildFfmpegArgs(
        '/Users/test/video.mp4',
        '/Users/test/thumb.jpg',
        atSecond: 2,
      );

      expect(args, contains('-y'));
      expect(args, contains('-ss'));
      expect(args, contains('00:00:02'));
      expect(args, contains('-i'));
      expect(args, contains('/Users/test/video.mp4'));
      expect(args, contains('-vframes'));
      expect(args, contains('1'));
      expect(args.last, equals('/Users/test/thumb.jpg'));
    });

    test('buildFallbackFfmpegArgs builds fallback extraction arguments at 0.5s', () {
      final args = ThumbnailManager.buildFallbackFfmpegArgs(
        '/Users/test/short_clip.mp4',
        '/Users/test/thumb.jpg',
      );

      expect(args, contains('-ss'));
      expect(args, contains('00:00:00.5'));
      expect(args.last, equals('/Users/test/thumb.jpg'));
    });

    test('thumbnailsDir is created during PrivateStorageManager init', () async {
      final tempRoot = Directory.systemTemp.createTempSync('storage_thumb_test');
      try {
        await PrivateStorageManager.instance.init(customRoot: tempRoot);
        expect(PrivateStorageManager.instance.thumbnailsDir.existsSync(), isTrue);
      } finally {
        tempRoot.deleteSync(recursive: true);
      }
    });

    test('DownloadTask preserves and updates thumbnailUrl', () {
      final task = DownloadTask(
        id: 't_thumb',
        url: 'https://example.com/video',
        title: 'Video with Thumbnail',
        thumbnailUrl: 'https://example.com/thumb.jpg',
      );

      expect(task.thumbnailUrl, equals('https://example.com/thumb.jpg'));

      task.update(newThumbnailUrl: 'https://example.com/new_thumb.jpg');
      expect(task.thumbnailUrl, equals('https://example.com/new_thumb.jpg'));
    });
  });
}
