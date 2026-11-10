import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:encrypt/encrypt.dart' as enc;
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/privacy_security_service.dart';
import 'package:V8WorkToolbox/tools/casual_short_drama/models/drama_models.dart';
import 'package:V8WorkToolbox/tools/casual_short_drama/services/huangguo_api_client.dart';
import 'package:V8WorkToolbox/tools/casual_short_drama/services/drama_cover_decryptor.dart';

void main() {
  group('HuangguoApiClient Tests', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('casual_api_test');
      AppPaths.overrideRootForTesting(tempDir);
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    test('edgeRequest correctly constructs envelope payload and parses response', () async {
      String? capturedUrl;
      Map<String, String>? capturedHeaders;
      String? capturedBody;

      final mockClient = MockClient((request) async {
        capturedUrl = request.url.toString();
        capturedHeaders = request.headers;
        capturedBody = request.body;

        final mockResponse = {
          'status': 1,
          'msg': 'ok',
          'data': {
            'items': [
              {
                'id': 1001,
                'title': '测试短剧：无敌小保安',
                'cover': 'https://example.com/cover1.jpg',
                'score': 9.2,
                'total_episodes': 60,
                'is_finished': true,
              }
            ],
            'pagination': {'page': 1, 'pages': 1, 'size': 20, 'total': 1}
          }
        };

        return http.Response(jsonEncode(mockResponse), 200, headers: {
          'content-type': 'application/json',
        });
      });

      final client = HuangguoApiClient(httpClient: mockClient);
      final feed = await client.getFeed(page: 1, size: 20);

      expect(capturedUrl, 'https://huangguoai.com/api/edge/request');
      expect(capturedHeaders?['Referer'], 'https://huangguoai.com/');
      expect(capturedHeaders?['Content-Type'], 'application/json');

      final envelope = jsonDecode(capturedBody!) as Map<String, dynamic>;
      expect(envelope['method'], 'GET');
      expect(envelope['path'], '/api/videos?page=1&size=20');

      expect(feed.length, 1);
      expect(feed.first.id, 1001);
      expect(feed.first.title, '测试短剧：无敌小保安');
      expect(feed.first.score, 9.2);
      expect(feed.first.isFinished, isTrue);
    });

    test('switchBase updates current base and changes referer', () async {
      final mockClient = MockClient((request) async {
        return http.Response(jsonEncode({'status': 1, 'data': {}}), 200);
      });

      final client = HuangguoApiClient(httpClient: mockClient);
      expect(client.currentBase, 'https://huangguoai.com');

      await client.switchBase('https://huangguoai.ai/');
      expect(client.currentBase, 'https://huangguoai.ai');

      expect(() => client.switchBase('http://insecure.com'), throwsArgumentError);
    });

    test('getPlayInfo prefers POST playback streams.main and falls back if needed', () async {
      String? requestedPath;
      String? requestedMethod;

      final mockClient = MockClient((request) async {
        final envelope = jsonDecode(request.body) as Map<String, dynamic>;
        requestedMethod = envelope['method'];
        requestedPath = envelope['path'];

        if (requestedPath == '/api/videos/123/episodes/1/playback') {
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'status': 1,
              'msg': 'ok',
              'data': {
                'episode': {
                  'id': 9991,
                  'video_id': 123,
                  'ep_num': 1,
                  'title': '第一集：龙王出狱',
                  'duration': 90,
                },
                'streams': {
                  'main': 'https://stream.example.com/live/ep1.m3u8',
                  'hevc': 'https://stream.example.com/live/ep1_hevc.m3u8',
                }
              }
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        return http.Response(jsonEncode({'status': 0, 'msg': 'not found'}), 404);
      });

      final client = HuangguoApiClient(httpClient: mockClient);
      final playInfo = await client.getPlayInfo(123, 1);

      expect(requestedMethod, 'POST');
      expect(requestedPath, '/api/videos/123/episodes/1/playback');
      expect(playInfo.id, 9991);
      expect(playInfo.epNum, 1);
      expect(playInfo.title, '第一集：龙王出狱');
      expect(playInfo.videoUrl, 'https://stream.example.com/live/ep1.m3u8');
      expect(playInfo.videoUrlHevc, 'https://stream.example.com/live/ep1_hevc.m3u8');
    });

    test('DramaPlayInfo.fromJson parses upstream actual response with string id and flat ep', () {
      final upstreamActual = {
        'mode': 1,
        'timestamp': 1794242400,
        'id': '12',
        'ep': 1,
        'streams': {
          'main': 'https://stream.example.com/videos5/main.m3u8?auth_key=abc',
          'hevc': 'https://stream.example.com/videos5/hevc.m3u8?auth_key=abc',
          'preview': 'https://stream.example.com/videos5/preview.m3u8?auth_key=abc',
        }
      };
      final info = DramaPlayInfo.fromJson(upstreamActual);
      expect(info.id, 12);
      expect(info.epNum, 1);
      expect(info.videoUrl, 'https://stream.example.com/videos5/main.m3u8?auth_key=abc');
    });

    test('DramaPlayInfo.fromJson falls back to preview stream if main is missing', () {
      final json = {
        'id': '88',
        'ep': 3,
        'streams': {
          'preview': 'https://stream.example.com/preview_only.m3u8',
        }
      };
      final info = DramaPlayInfo.fromJson(json);
      expect(info.id, 88);
      expect(info.epNum, 3);
      expect(info.videoUrl, 'https://stream.example.com/preview_only.m3u8');
    });

    test('DramaPlayInfo.fromJson parses legacy flat schema as well', () {
      final legacyJson = {
        'id': 1002,
        'ep_num': 2,
        'duration': 120,
        'title': '第2集',
        'video_url': 'https://stream.example.com/legacy/ep2.m3u8',
      };
      final info = DramaPlayInfo.fromJson(legacyJson);
      expect(info.id, 1002);
      expect(info.epNum, 2);
      expect(info.videoUrl, 'https://stream.example.com/legacy/ep2.m3u8');
    });
  });

  group('DramaCoverDecryptor Tests', () {
    test('plain images pass through without modification', () {
      final decryptor = DramaCoverDecryptor();

      // JPEG header
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46, 0x49, 0x46, 0x00, 0x01]);
      expect(DramaCoverDecryptor.isPlainImage(jpeg), isTrue);
      expect(decryptor.decryptBytes(jpeg), equals(jpeg));

      // PNG header
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D]);
      expect(DramaCoverDecryptor.isPlainImage(png), isTrue);
      expect(decryptor.decryptBytes(png), equals(png));
    });

    test('AES-128-CBC encrypted image payload is properly decrypted', () {
      final decryptor = DramaCoverDecryptor();

      // 构建一个带明文 JPEG 头的测试 payload，并使用静态密钥和 IV 加密
      final key = enc.Key(Uint8List.fromList(utf8.encode('f5d965df75336270')));
      final iv = enc.IV(Uint8List.fromList(utf8.encode('97b60394abc2fbe1')));
      final encrypter = enc.Encrypter(enc.AES(key, mode: enc.AESMode.cbc, padding: 'PKCS7'));

      final originalData = Uint8List.fromList([
        0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46,
        0x49, 0x46, 0x00, 0x01, 0xAA, 0xBB, 0xCC, 0xDD,
        0xEE, 0xFF, 0x11, 0x22,
      ]);

      final encrypted = encrypter.encryptBytes(originalData, iv: iv);
      final cipherBytes = Uint8List.fromList(encrypted.bytes);

      expect(cipherBytes.length % 16, 0);
      expect(DramaCoverDecryptor.isPlainImage(cipherBytes), isFalse);

      final decrypted = decryptor.decryptBytes(cipherBytes);
      expect(decrypted, equals(originalData));
      expect(DramaCoverDecryptor.isPlainImage(decrypted), isTrue);
    });

    test('stripPadding strips PKCS7 padding correctly', () {
      // 尾部填 4 个 0x04
      final buf = Uint8List.fromList([1, 2, 3, 4, 4, 4, 4, 4]);
      final stripped = DramaCoverDecryptor.stripPadding(buf);
      expect(stripped, equals(Uint8List.fromList([1, 2, 3, 4])));

      // 无填充
      final noPad = Uint8List.fromList([1, 2, 3, 4, 5]);
      expect(DramaCoverDecryptor.stripPadding(noPad), equals(noPad));
    });

    test('DramaSortType correctly sorts items by score and episodes', () {
      final items = [
        const DramaCard(id: 1, title: '剧集 A', cover: '', score: 7.5, totalEpisodes: 80),
        const DramaCard(id: 2, title: '剧集 B', cover: '', score: 9.8, totalEpisodes: 20),
        const DramaCard(id: 3, title: '剧集 C', cover: '', score: 8.9, totalEpisodes: 120),
      ];

      // 按评分降序
      final byScore = List<DramaCard>.from(items)..sort((a, b) => b.score.compareTo(a.score));
      expect(byScore.map((e) => e.id).toList(), [2, 3, 1]);
      expect(byScore.first.score, 9.8);

      // 按集数降序
      final byEpisodes = List<DramaCard>.from(items)..sort((a, b) => b.totalEpisodes.compareTo(a.totalEpisodes));
      expect(byEpisodes.map((e) => e.id).toList(), [3, 1, 2]);
      expect(byEpisodes.first.totalEpisodes, 120);
    });

    test('CasualShortDrama playback inhibitor suppresses auto-lock and refreshes activity', () {
      final privacyService = PrivacySecurityService.instance;
      bool simulatedPlaying = false;
      final PlaybackInhibitor inhibitor = () => simulatedPlaying;

      privacyService.registerPlaybackInhibitor(inhibitor);
      try {
        expect(privacyService.isPlaybackActive(), isFalse);

        // 模拟短剧开始播放
        simulatedPlaying = true;
        expect(privacyService.isPlaybackActive(), isTrue);

        // 模拟解锁状态并检测闲置抑制
        privacyService.isUnlockedNotifier.value = true;
        final timeoutTime = DateTime.now().add(const Duration(minutes: 10));
        final didLock = privacyService.checkIdleTimeout(currentTime: timeoutTime);

        // 正在播放中，绝不应锁屏
        expect(didLock, isFalse);
        expect(privacyService.isUnlocked, isTrue);

        // 停止播放后
        simulatedPlaying = false;
        expect(privacyService.isPlaybackActive(), isFalse);
      } finally {
        privacyService.unregisterPlaybackInhibitor(inhibitor);
      }
    });
  });
}
