import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/real_meeting_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/models/rehearsal_models.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/audio_toolkit.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_baker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/real_meeting_store.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/rehearsal_baker.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/rehearsal_voices.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/role_voice_map.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/speaker_profile_resolver.dart';
import 'package:V8WorkToolbox/tools/it_meeting_listening/services/tts_binding_probe.dart';
import 'package:V8WorkToolbox/tools/reader/models/reader_models.dart';
import 'package:V8WorkToolbox/tools/reader/services/tts_engine.dart';

/// TTS 槽位绑定到 MiMo 时的行为验证。
///
/// 覆盖真实会议「说话人与音色」链路的 MiMo 适配：
/// - TtsBindingProbe 的默认音色/风格/候选随绑定切换
/// - SpeakerProfileResolver 散列兜底在 MiMo 下产出 MiMo 合法音色
/// - adaptVoiceForProvider 对 MiMo 音色透传、对 StepFun id 兜底（回归锚点）
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const mimoProvider = AiProviderConfig(
    id: 'prov_mimo_test',
    name: 'Xiaomi MiMo',
    protocol: AiProtocolType.openai,
    baseUrl: 'https://api.xiaomimimo.com/v1',
    keychainKeyId: 'key_mimo_test',
    enabled: true,
    ttsModels: ['mimo-v2.5-tts'],
  );

  const stepProvider = AiProviderConfig(
    id: 'prov_step_test',
    name: 'StepFun',
    protocol: AiProtocolType.openai,
    baseUrl: 'https://api.stepfun.com/v1',
    keychainKeyId: 'key_step_test',
    enabled: true,
    ttsModels: ['stepaudio-2.5-tts'],
  );

  setUp(() async {
    // 测试用内存 Keychain 桥 + 干净的 AiConfigStore 单例。
    await AiConfigStore.instance.resetForTesting();
    await AiConfigStore.instance.init(customRootDir: Directory.systemTemp.createTempSync('tts_probe_test_'));
  });

  tearDown(() async {
    await AiConfigStore.instance.resetForTesting();
  });

  group('TtsBindingProbe 绑定探测', () {
    test('无绑定时默认走 StepFun 池', () {
      expect(TtsBindingProbe.isMimo(), isFalse);
      expect(TtsBindingProbe.defaultVoiceId(), VoicePool.zhixingjiejie.id);
      expect(TtsBindingProbe.defaultStyle(), '');
    });

    test('绑定 MiMo 时默认音色为 mimo_default 且风格指令非空', () async {
      await AiConfigStore.instance.saveProvider(mimoProvider);
      await AiConfigStore.instance.addSlotCandidate('tts', mimoProvider.id, 'mimo-v2.5-tts');

      expect(TtsBindingProbe.isMimo(), isTrue);
      expect(TtsBindingProbe.defaultVoiceId(), 'mimo_default');
      expect(TtsBindingProbe.defaultStyle(), isNotEmpty);
      // 候选包含 MiMo 官方音色
      final ids = TtsBindingProbe.voiceOptions().map((v) => v.id).toSet();
      expect(ids.contains('mimo_default'), isTrue);
      expect(ids.contains('冰糖'), isTrue);
    });

    test('绑定非 MiMo（StepFun）时沿用 VoicePool 行为', () async {
      await AiConfigStore.instance.saveProvider(stepProvider);
      await AiConfigStore.instance.addSlotCandidate('tts', stepProvider.id, 'stepaudio-2.5-tts');

      expect(TtsBindingProbe.isMimo(), isFalse);
      expect(TtsBindingProbe.defaultVoiceId(), VoicePool.zhixingjiejie.id);
      expect(TtsBindingProbe.defaultStyle(), '');
      // 候选与 VoicePool 等价
      final ids = TtsBindingProbe.voiceOptions().map((v) => v.id).toSet();
      expect(ids, VoicePool.all.map((v) => v.id).toSet());
    });
  });

  group('SpeakerProfileResolver 散列兜底在 MiMo 下', () {
    const identity = MyIdentity(name: '我', voiceId: 'boyinnansheng');

    test('产出 MiMo 合法音色且不同槽位高概率不同', () {
      final mimoIds = TtsVoiceOption.defaultMimoVoices.map((v) => v.id).toList();
      final slots = ['发言人 1', '发言人 2', '发言人 3', '发言人 4', '发言人 5'];
      final resolved = slots
          .map((s) => SpeakerProfileResolver.resolve(
                slotId: s,
                setting: const SpeakerSetting(),
                identity: identity,
                fallbackVoiceIds: mimoIds,
              ).voiceId)
          .toList();

      // 全部落在 MiMo 支持列表内
      for (final v in resolved) {
        expect(TtsVoiceOption.mimoSupportedVoiceIds.contains(v), isTrue,
            reason: '$v 应在 MiMo 支持列表内');
      }
      // 不同槽位大概率不同（至少 >1 种）
      expect(resolved.toSet().length, greaterThan(1));
      // 同一槽位两次解析一致（纯函数）
      final again = SpeakerProfileResolver.resolve(
        slotId: '发言人 1',
        setting: const SpeakerSetting(),
        identity: identity,
        fallbackVoiceIds: mimoIds,
      ).voiceId;
      expect(again, resolved.first);
    });

    test('不传候选池时仍走既有 VoicePool（非 MiMo 兼容）', () {
      final r = SpeakerProfileResolver.resolve(
        slotId: '发言人 1',
        setting: const SpeakerSetting(),
        identity: identity,
      );
      expect(VoicePool.all.map((v) => v.id), contains(r.voiceId));
    });
  });

  group('adaptVoiceForProvider 透传与兜底', () {
    test('MiMo 音色直接透传不被替换', () {
      for (final v in TtsVoiceOption.defaultMimoVoices) {
        final adapted = OpenAiTtsEngine.adaptVoiceForProvider(
          v.id,
          isQwen: false,
          isMimo: true,
          isStepFun: false,
          isOpenAi: false,
        );
        expect(adapted, v.id, reason: 'MiMo 音色 ${v.id} 应透传而非被替换');
      }
    });

    test('StepFun id 在 MiMo 下被兜底为 mimo_default（原缺陷锚点）', () {
      // 这是本变更修复的根因：VoicePool 与 mimoSupportedVoiceIds 零交集，
      // 任何 VoicePool id 在 MiMo 下都会静默变成 mimo_default。
      for (final v in VoicePool.all) {
        final adapted = OpenAiTtsEngine.adaptVoiceForProvider(
          v.id,
          isQwen: false,
          isMimo: true,
          isStepFun: false,
          isOpenAi: false,
        );
        expect(adapted, 'mimo_default');
      }
    });

    test('MiMo 音色 id 与 VoicePool 零交集', () {
      final mimo = TtsVoiceOption.mimoSupportedVoiceIds;
      final step = VoicePool.all.map((v) => v.id).toSet();
      expect(mimo.intersection(step), isEmpty);
    });
  });

  group('RehearsalVoices 在 MiMo 下', () {
    setUp(() async {
      await AiConfigStore.instance.saveProvider(mimoProvider);
      await AiConfigStore.instance
          .addSlotCandidate('tts', mimoProvider.id, 'mimo-v2.5-tts');
    });

    test('5 个角色映射到 5 个互不相同的 MiMo 合法音色', () {
      expect(TtsBindingProbe.isMimo(), isTrue);
      final ids = RehearsalVoices.all.keys
          .map((roleId) => RehearsalVoices.voiceFor(roleId))
          .toList();
      expect(ids, hasLength(5));
      expect(ids.toSet(), hasLength(5));
      for (final v in ids) {
        expect(TtsVoiceOption.mimoSupportedVoiceIds.contains(v), isTrue,
            reason: '$v 应在 MiMo 支持列表内');
      }
    });
  });

  group('RealMeetingBaker 与 RehearsalBaker 在 MiMo 下注入与透传', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('probe_baker_test_');
      AppPaths.overrideRootForTesting(tempDir);
    });

    tearDown(() async {
      AppPaths.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('RealMeetingBaker 在 MiMo 下注入 styleInstruction 且透传 MiMo 音色', () async {
      await AiConfigStore.instance.saveProvider(mimoProvider);
      await AiConfigStore.instance
          .addSlotCandidate('tts', mimoProvider.id, 'mimo-v2.5-tts');

      final fakeTts = _ProbeBakerTts();
      final fakeAudio = _ProbeBakerAudio();
      final store = RealMeetingStore();
      final baker = RealMeetingBaker(engine: fakeTts, store: store, audio: fakeAudio);

      final meeting = RealMeeting(
        id: 'rm_probe_test',
        title: 'MiMo Test',
        sourcePath: '/test.md',
        fileName: 'test.md',
        contentHash: 'hash_test',
        declaredDurationMs: 0,
        keywords: const [],
        slots: const [SpeakerSlot(id: 'Speaker A', turnCount: 1)],
        turns: const [
          MeetingTurn(index: 0, slotId: 'Speaker A', timestampMs: 0, text: 'Hello team.'),
        ],
        importedAt: DateTime(2026, 11, 3),
      );

      final speakers = <String, ResolvedSpeaker>{
        'Speaker A': const ResolvedSpeaker(
          slotId: 'Speaker A',
          displayName: 'Speaker A',
          voiceId: '冰糖',
          isMe: false,
        ),
      };

      await baker.bake(meeting, speakers: speakers);

      expect(fakeTts.recorded, isNotEmpty);
      final cfg = fakeTts.recorded.first.config;
      expect(cfg.customVoiceId, '冰糖');
      expect(cfg.effectiveVoiceId, '冰糖');
      expect(cfg.styleInstruction, TtsBindingProbe.defaultStyle());
      expect(cfg.styleInstruction, isNotEmpty);
    });

    test('RealMeetingBaker 在非 MiMo 下 styleInstruction 为空', () async {
      await AiConfigStore.instance.saveProvider(stepProvider);
      await AiConfigStore.instance
          .addSlotCandidate('tts', stepProvider.id, 'stepaudio-2.5-tts');

      final fakeTts = _ProbeBakerTts();
      final fakeAudio = _ProbeBakerAudio();
      final store = RealMeetingStore();
      final baker = RealMeetingBaker(engine: fakeTts, store: store, audio: fakeAudio);

      final meeting = RealMeeting(
        id: 'rm_probe_test_step',
        title: 'Step Test',
        sourcePath: '/test.md',
        fileName: 'test.md',
        contentHash: 'hash_step',
        declaredDurationMs: 0,
        keywords: const [],
        slots: const [SpeakerSlot(id: 'Speaker A', turnCount: 1)],
        turns: const [
          MeetingTurn(index: 0, slotId: 'Speaker A', timestampMs: 0, text: 'Hello team.'),
        ],
        importedAt: DateTime(2026, 11, 3),
      );

      final speakers = <String, ResolvedSpeaker>{
        'Speaker A': ResolvedSpeaker(
          slotId: 'Speaker A',
          displayName: 'Speaker A',
          voiceId: VoicePool.zhixingjiejie.id,
          isMe: false,
        ),
      };

      await baker.bake(meeting, speakers: speakers);

      expect(fakeTts.recorded, isNotEmpty);
      final cfg = fakeTts.recorded.first.config;
      expect(cfg.customVoiceId, VoicePool.zhixingjiejie.id);
      expect(cfg.styleInstruction, '');
    });

    test('RehearsalBaker 在 MiMo 下注入 styleInstruction 且使用 MiMo 角色音色', () async {
      await AiConfigStore.instance.saveProvider(mimoProvider);
      await AiConfigStore.instance
          .addSlotCandidate('tts', mimoProvider.id, 'mimo-v2.5-tts');

      final fixture = await _makeMp3Fixture(tempDir);
      final fakeTts = _ProbeBakerTts(responseBytes: fixture);
      final matDir = Directory(p.join(tempDir.path, 'mat'));
      final cacheDir = Directory(p.join(tempDir.path, 'cache'));
      final baker = RehearsalBaker(engine: fakeTts, materialDir: matDir, cacheDir: cacheDir);

      final script = MeetingScript(
        id: 'script_probe_test',
        materialId: 'mat_probe_test',
        draftId: 'draft_probe_test',
        title: 'Rehearsal MiMo Test',
        targetMinutes: 10,
        generatedAt: DateTime(2026, 11, 3),
        turns: const [
          ScriptTurn(
            role: RehearsalRole.simon,
            text: 'Let us begin.',
            phase: ScriptPhase.topics,
          ),
        ],
      );

      await baker.bake(script);

      expect(fakeTts.recorded, isNotEmpty);
      final cfg = fakeTts.recorded.first.config;
      final expectedVoice = RehearsalVoices.voiceFor('simon');
      expect(TtsVoiceOption.mimoSupportedVoiceIds.contains(expectedVoice), isTrue);
      expect(cfg.customVoiceId, expectedVoice);
      expect(cfg.styleInstruction, TtsBindingProbe.defaultStyle());
      expect(cfg.styleInstruction, isNotEmpty);
    });
  });

  group('跨供应商非法音色自动清洗与待更新对齐', () {
    const identity = MyIdentity(name: '我', voiceId: 'boyinnansheng');

    test('MeetingSpeakerSettings.sanitizeVoices 能识别并清洗跨厂商非法音色', () {
      final settings = MeetingSpeakerSettings(
        bySlot: {
          '发言人 1': const SpeakerSetting(voiceId: '白桦'), // 合法 MiMo 音色
          '发言人 2': const SpeakerSetting(voiceId: 'shenchennanyin'), // 非法 StepFun 音色
          '发言人 3': const SpeakerSetting(voiceId: ''), // 未指定
          '发言人 4': const SpeakerSetting(voiceId: 'custom_voice'), // 普通自定义音色不误杀
        },
      );

      // 模拟处于 MiMo 环境
      final (cleaned, changed) = settings.sanitizeVoices((v) => VoicePool.all.any((p) => p.id == v));

      expect(changed, isTrue);
      expect(cleaned.of('发言人 1').voiceId, '白桦');
      expect(cleaned.of('发言人 2').voiceId, ''); // 被清洗重置为空
      expect(cleaned.of('发言人 3').voiceId, '');
      expect(cleaned.of('发言人 4').voiceId, 'custom_voice');
    });

    test('SpeakerProfileResolver.resolve 跨厂商非法音色自动回退到当前合法散列音色', () {
      final fallbackMimoList = ['mimo_default', '白桦', '苏打', 'Dean'];

      // 发言人 2 历史遗留了 StepFun 的 'shenchennanyin'
      final resolved = SpeakerProfileResolver.resolve(
        slotId: '发言人 2',
        setting: const SpeakerSetting(voiceId: 'shenchennanyin'),
        identity: identity,
        fallbackVoiceIds: fallbackMimoList,
        isIncompatibleVoice: (v) => VoicePool.all.any((p) => p.id == v),
      );

      // 不应保留 'shenchennanyin'，应回退到 MiMo 合法散列音色
      expect(resolved.voiceId, isNot('shenchennanyin'));
      expect(fallbackMimoList.contains(resolved.voiceId), isTrue);
    });

    test('RealMeetingStore.loadMyIdentity 跨供应商时自动双向清洗', () async {
      final tempDir = Directory.systemTemp.createTempSync('identity_test_');
      AppPaths.overrideRootForTesting(tempDir);

      try {
        // 先设为 MiMo
        await AiConfigStore.instance.saveProvider(mimoProvider);
        await AiConfigStore.instance.addSlotCandidate('tts', mimoProvider.id, 'mimo-v2.5-tts');

        final store = RealMeetingStore();
        // 存储了 StepFun 的 boyinnansheng
        await store.saveMyIdentity(const MyIdentity(name: 'Simon', voiceId: 'boyinnansheng'));

        final loadedInMimo = await store.loadMyIdentity();
        // 在 MiMo 下应自动回退为 mimo_default
        expect(loadedInMimo.voiceId, 'mimo_default');

        // 切换回 StepFun
        await AiConfigStore.instance.resetForTesting();
        await AiConfigStore.instance.init(customRootDir: tempDir);
        await AiConfigStore.instance.saveProvider(stepProvider);
        await AiConfigStore.instance.addSlotCandidate('tts', stepProvider.id, 'stepaudio-2.5-tts');

        // 存储了 MiMo 的 白桦
        await store.saveMyIdentity(const MyIdentity(name: 'Simon', voiceId: '白桦'));
        final loadedInStep = await store.loadMyIdentity();
        // 在 StepFun 下应自动回退为 StepFun 默认音色
        expect(loadedInStep.voiceId, VoicePool.zhixingjiejie.id);
      } finally {
        AppPaths.resetForTesting();
      }
    });
  });
}

Future<Uint8List> _makeMp3Fixture(Directory dir) async {
  final out = p.join(dir.path, 'fixture.mp3');
  final r = await Process.run('ffmpeg', [
    '-y',
    '-loglevel',
    'error',
    '-f',
    'lavfi',
    '-i',
    'anullsrc=r=24000:cl=mono',
    '-t',
    '0.5',
    '-b:a',
    '128k',
    out,
  ]);
  if (r.exitCode != 0) {
    throw StateError('无法生成测试固件（需要 ffmpeg）: ${r.stderr}');
  }
  return Uint8List.fromList(await File(out).readAsBytes());
}

class _ProbeBakerTts implements TtsEngine {
  final List<({String text, TtsSynthesisConfig config})> recorded = [];
  final Uint8List responseBytes;

  _ProbeBakerTts({Uint8List? responseBytes})
      : responseBytes = responseBytes ?? Uint8List.fromList(List.filled(16, 0));

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Uint8List> synthesize(String text, TtsSynthesisConfig config) async {
    recorded.add((text: text, config: config));
    return responseBytes;
  }
}

class _ProbeBakerAudio implements AudioToolkit {
  @override
  Future<void> concat(List<String> files, String outputPath) async {
    await File(outputPath).writeAsBytes(const [0]);
  }

  @override
  Future<int> probeDurationMs(String filePath) async => 100;

  @override
  Future<void> writeSilence(String path, int ms) async {
    await File(path).writeAsBytes(const [0]);
  }
}
