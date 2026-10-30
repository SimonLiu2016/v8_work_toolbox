/// 实时会议翻译工具的单元测试。
///
/// 覆盖 VAD 分块、字幕模型、SRT/VTT 导出（spec: live-audio-capture、
/// subtitle-export-with-speakers）。ASR SSE 与翻译依赖网络，不在单元测试范围。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:V8WorkToolbox/tools/live_translator/models/caption_segment.dart';
import 'package:V8WorkToolbox/tools/live_translator/models/capture_config.dart';
import 'package:V8WorkToolbox/tools/live_translator/models/speaker_state.dart';
import 'package:V8WorkToolbox/tools/live_translator/services/audio_capture_service.dart';
import 'package:V8WorkToolbox/tools/live_translator/services/live_translator_coordinator.dart';
import 'package:V8WorkToolbox/tools/live_translator/services/openrouter_asr_client.dart';
import 'package:V8WorkToolbox/tools/live_translator/services/stepfun_asr_client.dart';
import 'package:V8WorkToolbox/tools/live_translator/services/vad_chunker.dart';
import 'package:V8WorkToolbox/shell/ai_config_page.dart';

/// 预选优先级逻辑（与 live_translator_page._preselect 同规则的纯函数版，
/// 避免测 UI State 而拉起 Flutter 引擎）。
///
/// 优先级：记忆（索引范围内且名字匹配）> 虚拟声卡关键词 > 第一个。
const _virtualDeviceKeywords = [
  'soundflower',
  'blackhole',
  '虚拟',
  'aggregate',
  '聚集',
];

AudioCaptureDevice? _preselect(
  List<AudioCaptureDevice> devices,
  int? savedIndex,
  String? savedName,
) {
  if (devices.isEmpty) return null;
  if (savedIndex != null && savedName != null) {
    final match = devices.cast<AudioCaptureDevice?>().firstWhere(
          (d) => d?.deviceIndex == savedIndex && d?.name == savedName,
          orElse: () => null,
        );
    if (match != null) return match;
  }
  for (final d in devices) {
    final lower = d.name.toLowerCase();
    if (_virtualDeviceKeywords.any((k) => lower.contains(k.toLowerCase()))) {
      return d;
    }
  }
  return devices.first;
}

AudioCaptureDevice _dev(int index, String name) =>
    AudioCaptureDevice(name: name, channels: 2, deviceIndex: index);

/// 生成一段 16-bit PCM：前 silentSec 秒静音，后 speechSec 秒为方波（有能量）。
Uint8List _makePcm({
  required int sampleRate,
  required double silentSec,
  required double speechSec,
}) {
  final silentSamples = (sampleRate * silentSec).round();
  final speechSamples = (sampleRate * speechSec).round();
  final total = (silentSamples + speechSamples) * 2;
  final bytes = Uint8List(total);
  // 静音段全 0；语音段填一个高振幅方波（±20000），保证 RMS 超阈值。
  var offset = silentSamples * 2;
  var sample = 0;
  while (sample < speechSamples) {
    final value = (sample ~/ 8).isEven ? 20000 : -20000;
    bytes[offset] = value & 0xFF;
    bytes[offset + 1] = (value >> 8) & 0xFF;
    offset += 2;
    sample++;
  }
  return bytes;
}

void main() {
  group('StepFun ASR 端点自适应解析与预设', () {
    test('StepFunPreset 常量符合官方规范', () {
      expect(StepFunPreset.baseUrl, 'https://api.stepfun.com/v1');
      expect(
        StepFunPreset.stepPlanBaseUrl,
        'https://api.stepfun.com/step_plan/v1',
      );
      expect(StepFunPreset.sttModels, contains('stepaudio-2.5-asr'));
      expect(StepFunPreset.ttsModels, contains('stepaudio-2.5-tts'));
    });

    test('resolveAsrEndpoint 兼容开放平台常规路径', () {
      expect(
        LiveTranslatorCoordinator.resolveAsrEndpoint(
          'https://api.stepfun.com/v1',
        ),
        'https://api.stepfun.com/v1/audio/asr/sse',
      );
      expect(
        LiveTranslatorCoordinator.resolveAsrEndpoint(
          'https://api.stepfun.com/v1/',
        ),
        'https://api.stepfun.com/v1/audio/asr/sse',
      );
    });

    test('resolveAsrEndpoint 兼容 Step Plan 专属路径', () {
      expect(
        LiveTranslatorCoordinator.resolveAsrEndpoint(
          'https://api.stepfun.com/step_plan/v1',
        ),
        'https://api.stepfun.com/step_plan/v1/audio/asr/sse',
      );
      expect(
        LiveTranslatorCoordinator.resolveAsrEndpoint(
          'https://api.stepfun.com/step_plan/v1/',
        ),
        'https://api.stepfun.com/step_plan/v1/audio/asr/sse',
      );
    });

    test('resolveAsrEndpoint 兼容已提供完整端点或裸域名', () {
      expect(
        LiveTranslatorCoordinator.resolveAsrEndpoint('https://api.stepfun.com'),
        'https://api.stepfun.com/v1/audio/asr/sse',
      );
      expect(
        LiveTranslatorCoordinator.resolveAsrEndpoint(
          'https://api.stepfun.com/step_plan/v1/audio/asr/sse',
        ),
        'https://api.stepfun.com/step_plan/v1/audio/asr/sse',
      );
    });

    test('未配置 ASR 时 start 抛出 StateError 并更新状态', () async {
      final coord = LiveTranslatorCoordinator();
      await expectLater(
        coord.start('ffmpeg'),
        throwsA(isA<StateError>()),
      );
      expect(coord.state.status, LiveStatus.error);
      expect(coord.state.lastError, contains('语音识别 (STT) 供应商'));
    });
  });

  group('AudioCaptureService.parseDeviceList', () {
    test('解析现代 FFmpeg 8.x 带日志前缀的设备列表', () {
      const output = '''
ffmpeg version 8.0.1 Copyright (c) 2000-2025 the FFmpeg developers
[AVFoundation indev @ 0x7fbaa49049c0] AVFoundation video devices:
[AVFoundation indev @ 0x7fbaa49049c0] [0] FaceTime高清相机（内建）
[AVFoundation indev @ 0x7fbaa49049c0] [1] Capture screen 0
[AVFoundation indev @ 0x7fbaa49049c0] AVFoundation audio devices:
[AVFoundation indev @ 0x7fbaa49049c0] [0] 聚集设备
[AVFoundation indev @ 0x7fbaa49049c0] [1] MacBook Pro麦克风
[AVFoundation indev @ 0x7fbaa49049c0] [2] Microsoft Teams Audio
[AVFoundation indev @ 0x7fbaa49049c0] [3] WeMeet Audio Device
[AVFoundation indev @ 0x7fbaa49049c0] [4] 外置麦克风
[AVFoundation indev @ 0x7fbaa49049c0] [5] Soundflower (64ch)
[AVFoundation indev @ 0x7fbaa49049c0] [6] Soundflower (2ch)
[AVFoundation indev @ 0x7fbaa49049c0] [7] 豆包会议记录虚拟设备
[in#0 @ 0x7fbaa3704840] Error opening input: Input/output error
Error opening input file .
''';
      final devices = AudioCaptureService.parseDeviceList(output);
      expect(devices.length, 8);
      expect(devices[0].deviceIndex, 0);
      expect(devices[0].name, '聚集设备');
      expect(devices[0].channels, 1);

      expect(devices[1].deviceIndex, 1);
      expect(devices[1].name, 'MacBook Pro麦克风');
      expect(devices[1].channels, 1);

      expect(devices[5].deviceIndex, 5);
      expect(devices[5].name, 'Soundflower (64ch)');
      expect(devices[5].channels, 64);

      expect(devices[6].deviceIndex, 6);
      expect(devices[6].name, 'Soundflower (2ch)');
      expect(devices[6].channels, 2);

      expect(devices[7].deviceIndex, 7);
      expect(devices[7].name, '豆包会议记录虚拟设备');
      expect(devices[7].channels, 1);
    });

    test('解析旧版/无前缀 FFmpeg 输出', () {
      const output = '''
[AVFoundation input device @ 0x7f9a1b000000] AVFoundation video devices:
[AVFoundation input device @ 0x7f9a1b000000] [0] FaceTime HD Camera
[AVFoundation input device @ 0x7f9a1b000000] AVFoundation audio devices:
[0] Built-in Microphone
[1] Soundflower (2ch)
[2] BlackHole 2ch (2ch)
''';
      final devices = AudioCaptureService.parseDeviceList(output);
      expect(devices.length, 3);
      expect(devices[0].deviceIndex, 0);
      expect(devices[0].name, 'Built-in Microphone');
      expect(devices[0].channels, 1);
      expect(devices[1].deviceIndex, 1);
      expect(devices[1].name, 'Soundflower (2ch)');
      expect(devices[1].channels, 2);
      expect(devices[2].deviceIndex, 2);
      expect(devices[2].name, 'BlackHole 2ch (2ch)');
      expect(devices[2].channels, 2);
    });

    test('空输出或未包含音频设备时返回空列表', () {
      expect(AudioCaptureService.parseDeviceList(''), isEmpty);
      expect(AudioCaptureService.parseDeviceList('Some random error'), isEmpty);
      expect(
        AudioCaptureService.parseDeviceList('AVFoundation video devices:\n[0] Camera'),
        isEmpty,
      );
    });

    test('兼容 Windows 风格回车换行 \\r\\n', () {
      const output =
          'AVFoundation audio devices:\r\n[0] Mic\r\n[1] Stereo (2ch)\r\n';
      final devices = AudioCaptureService.parseDeviceList(output);
      expect(devices.length, 2);
      expect(devices[0].name, 'Mic');
      expect(devices[1].name, 'Stereo (2ch)');
      expect(devices[1].channels, 2);
    });
  });

  group('设备预选优先级', () {
    final devices = [
      _dev(1, 'MacBook Pro麦克风'),
      _dev(5, 'Soundflower (2ch)'),
      _dev(6, '聚集设备'),
    ];

    test('记忆的设备仍存在时优先恢复（即使不是第一个）', () {
      final picked = _preselect(devices, 6, '聚集设备');
      expect(picked?.deviceIndex, 6);
    });

    test('记忆的索引存在但名字对不上（重枚举偏移）时走关键词回退', () {
      // 索引 1 现在指向了 Soundflower，但记忆的名字是麦克风 → 视为失效。
      final picked = _preselect(devices, 1, 'MacBook Pro麦克风'.replaceAll('麦克风', 'X'));
      expect(picked?.deviceIndex, 5); // 关键词命中 Soundflower
    });

    test('无记忆时优先虚拟声卡而非麦克风', () {
      final picked = _preselect(devices, null, null);
      expect(picked?.name, 'Soundflower (2ch)');
    });

    test('无记忆且无虚拟声卡时回退第一个', () {
      final micsOnly = [_dev(1, 'MacBook Pro麦克风')];
      final picked = _preselect(micsOnly, null, null);
      expect(picked?.deviceIndex, 1);
    });

    test('空列表返回 null', () {
      expect(_preselect(const [], null, null), isNull);
    });
  });

  group('VadChunker.computeRms', () {
    test('静音 PCM 的 RMS 接近 0', () {
      final pcm = Uint8List(320); // 160 个 0 采样
      expect(VadChunker.computeRms(pcm), lessThan(1.0));
    });

    test('方波 PCM 的 RMS 接近振幅', () {
      final bytes = <int>[];
      for (var i = 0; i < 100; i++) {
        final v = 20000;
        bytes.addAll([v & 0xFF, (v >> 8) & 0xFF]);
      }
      expect(VadChunker.computeRms(bytes), closeTo(20000, 500));
    });
  });

  group('VadChunker 分块', () {
    test('纯静音不产出音频块', () async {
      final config = CaptureConfig(energyThreshold: 500);
      final chunker = VadChunker(config);
      final chunks = <AudioChunk>[];
      chunker.chunkStream.listen(chunks.add);

      chunker.addPcm(_makePcm(
        sampleRate: 16000,
        silentSec: 3,
        speechSec: 0,
      ));
      await Future.delayed(const Duration(milliseconds: 50));

      expect(chunks, isEmpty);
      await chunker.dispose();
    });

    test('语音累积到块长即切块', () async {
      final config = CaptureConfig(
        energyThreshold: 500,
        chunkSeconds: 2,
        overlapSeconds: 0.5,
      );
      final chunker = VadChunker(config);
      final chunks = <AudioChunk>[];
      chunker.chunkStream.listen(chunks.add);

      // 6 秒语音应至少产出 2 块。
      chunker.addPcm(_makePcm(
        sampleRate: 16000,
        silentSec: 0,
        speechSec: 6,
      ));
      chunker.flush();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(chunks.length, greaterThanOrEqualTo(2));
      // 除最后一块（flush 的尾部可能不足一块）外，满块约 2s = 64000 字节。
      for (var i = 0; i < chunks.length - 1; i++) {
        expect(chunks[i].data.length, greaterThan(60000));
      }
      // 最后一块至少非空。
      expect(chunks.last.data.isNotEmpty, true);
      await chunker.dispose();
    });
  });

  group('SpeakerState', () {
    test('默认 3 槽位、激活第 0 个', () {
      final s = SpeakerState();
      expect(s.slots.length, 3);
      expect(s.activeIndex, 0);
      expect(s.active.name, '说话人 1');
    });

    test('切换激活槽位且越界忽略', () {
      final s = SpeakerState();
      s.setActive(2);
      expect(s.activeIndex, 2);
      s.setActive(9);
      expect(s.activeIndex, 2);
    });
  });

  group('CaptionSegment', () {
    test('copyWith 更新字段并保留 id', () {
      final seg = CaptionSegment(
        id: 'x',
        text: 'hello',
        speakerSlot: 1,
        startMs: 0,
        endMs: 0,
      );
      final done = seg.copyWith(
        text: 'world',
        isFinal: true,
        endMs: 2000,
        speakerSlot: 2,
      );
      expect(done.id, 'x');
      expect(done.text, 'world');
      expect(done.isFinal, true);
      expect(done.endMs, 2000);
      expect(done.speakerSlot, 2);
    });

    test('LiveTranslatorCoordinator.setActiveSpeaker 同步联动最新未定稿字幕的 speakerSlot', () {
      final coordinator = LiveTranslatorCoordinator();
      final segFinal = CaptionSegment(
        id: '1',
        text: 'Hello from speaker 0',
        speakerSlot: 0,
        startMs: 0,
        endMs: 1000,
        isFinal: true,
      );
      final segPending = CaptionSegment(
        id: '2',
        text: 'I am talking right now...',
        speakerSlot: 0,
        startMs: 1000,
        endMs: 0,
        isFinal: false,
      );

      // 模拟当前已有已定稿和在途字幕
      coordinator.stateForTesting = coordinator.state.copyWith(
        captions: [segFinal, segPending],
      );

      // 切换到说话人 2 (slot: 1)
      coordinator.setActiveSpeaker(1);

      expect(coordinator.state.speaker.activeIndex, 1);
      // 已定稿的字幕槽位保持不变
      expect(coordinator.state.captions[0].speakerSlot, 0);
      // 在途未定稿字幕段被动态同步为最新选中的说话人 2 (slot: 1)
      expect(coordinator.state.captions[1].speakerSlot, 1);
    });
  });

  group('CaptureConfig & LiveState', () {
    test('CaptureConfig 默认能量阈值为 50.0 且默认 2 通道', () {
      final config = CaptureConfig();
      expect(config.energyThreshold, 50.0);
      expect(config.deviceChannels, 2);
    });

    test('LiveState inputRms 属性与 copyWith 生效', () {
      final state = LiveState(
        status: LiveStatus.idle,
        captions: [],
        speaker: SpeakerState(),
        isRecording: false,
        translationEnabled: true,
        targetLanguage: 'zh',
        inputRms: 12.5,
      );
      expect(state.inputRms, 12.5);
      final updated = state.copyWith(inputRms: 120.0);
      expect(updated.inputRms, 120.0);
    });
  });

  group('StepFunAsrClient 402 Quota Remediation', () {
    test('402 发生时且非 step_plan endpoint 时提示切换到 step_plan/v1', () async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response('{"error":{"message":"quota_exceeded"}}', 402);
      });
      final client = StepFunAsrClient(
        apiKey: 'test-key',
        endpoint: 'https://api.stepfun.com/v1/audio/asr/sse',
        client: mockClient,
      );

      expect(
        () => client.transcribe([0, 0, 0, 0]).toList(),
        throwsA(isA<AsrException>().having(
          (e) => e.detail,
          'detail',
          contains('step_plan/v1'),
        )),
      );
    });
  });

  group('OpenRouter ASR 与预设', () {
    test('OpenRouterPreset 常量与默认值符合规范', () {
      expect(OpenRouterPreset.displayName, 'OpenRouter');
      expect(OpenRouterPreset.baseUrl, 'https://openrouter.ai/api/v1');
      expect(OpenRouterPreset.sttModels, 'qwen/qwen3-asr-0.6b');
      expect(OpenRouterPreset.textModels, contains('deepseek-r1'));
    });

    test('OpenRouterAsrClient.resolveEndpoint 正确解析各种 Base URL', () {
      expect(
        OpenRouterAsrClient.resolveEndpoint('https://openrouter.ai/api/v1'),
        'https://openrouter.ai/api/v1/audio/transcriptions',
      );
      expect(
        OpenRouterAsrClient.resolveEndpoint('https://openrouter.ai/api/v1/'),
        'https://openrouter.ai/api/v1/audio/transcriptions',
      );
      expect(
        OpenRouterAsrClient.resolveEndpoint(
          'https://openrouter.ai/api/v1/audio/transcriptions',
        ),
        'https://openrouter.ai/api/v1/audio/transcriptions',
      );
    });

    test('OpenRouterAsrClient.pcmToWav 生成合法的 44 字节 RIFF/WAV 头', () {
      final pcm = Uint8List(1600); // 800 个 16-bit 样本
      final wav = OpenRouterAsrClient.pcmToWav(pcm, sampleRate: 16000);

      expect(wav.length, 44 + 1600);
      // 'RIFF'
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      // 'WAVE'
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      // 'fmt '
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      // 'data'
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
    });

    test('OpenRouterAsrClient.transcribe 成功发送请求并产出 AsrEvent.done', () async {
      final mockClient = http_testing.MockClient((request) async {
        expect(request.url.toString(),
            'https://openrouter.ai/api/v1/audio/transcriptions');
        expect(request.headers['Authorization'], 'Bearer sk-test-openrouter');
        expect(request.headers['Content-Type'], 'application/json');

        return http.Response.bytes(
          utf8.encode(
            '{"text":"这是来自 OpenRouter Qwen3 ASR 的识别结果","usage":{"seconds":2.5}}',
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });

      final client = OpenRouterAsrClient(
        apiKey: 'sk-test-openrouter',
        client: mockClient,
      );

      final events = await client.transcribe([0, 1, 2, 3]).toList();
      expect(events.length, 1);
      expect(events.first.type, AsrEventType.done);
      expect(events.first.text, '这是来自 OpenRouter Qwen3 ASR 的识别结果');
    });

    test('OpenRouterAsrClient 识别 401 鉴权失败并抛出归因 AsrException', () async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response(
          '{"error":{"code":401,"message":"User key not found"}}',
          401,
        );
      });

      final client = OpenRouterAsrClient(
        apiKey: 'invalid-key',
        client: mockClient,
      );

      expect(
        () => client.transcribe([0, 0]).toList(),
        throwsA(isA<AsrException>().having(
          (e) => e.kind,
          'kind',
          AsrErrorKind.auth,
        )),
      );
    });

    test('OpenRouterAsrClient 识别 402 余额不足并抛出归因 AsrException', () async {
      final mockClient = http_testing.MockClient((request) async {
        return http.Response(
          '{"error":{"code":402,"message":"Insufficient credits"}}',
          402,
        );
      });

      final client = OpenRouterAsrClient(
        apiKey: 'no-credit-key',
        client: mockClient,
      );

      expect(
        () => client.transcribe([0, 0]).toList(),
        throwsA(isA<AsrException>().having(
          (e) => e.kind,
          'kind',
          AsrErrorKind.quota,
        )),
      );
    });
  });
}
