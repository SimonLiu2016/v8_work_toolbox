import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/media_capability.dart';
import 'package:V8WorkToolbox/tools/dola_pool/services/dola_pool_video_adapter.dart';

/// 能力矩阵的纯函数契约（spec: 模型能力声明 / 请求参数规整）。
///
/// 固定四件事：
/// 1. 声明命中就用声明，不猜；
/// 2. 未命中按协议取保守默认，且 `isDeclared` 为 false（UI 要能区分）；
/// 3. 吸附方向是「向下取整」——不超过用户预期这条不可破坏；
/// 4. 分辨率按**比例距离**吸附，不按像素差。
void main() {
  AiProviderConfig provider({
    AiProtocolType protocol = AiProtocolType.openai,
    Map<String, MediaModelCapability> capabilities = const {},
  }) {
    return AiProviderConfig(
      id: 'p1',
      name: '测试供应商',
      protocol: protocol,
      baseUrl: 'https://api.example.com',
      keychainKeyId: 'k1',
      mediaCapabilities: capabilities,
    );
  }

  group('声明命中', () {
    test('按模型 id 取出声明', () {
      const declared = MediaModelCapability(
        durations: [4, 8, 12],
        resolutions: ['720p'],
        ratios: ['9:16'],
        maxReferenceImages: 3,
        supportsFirstFrame: true,
        isDeclared: true,
      );
      final resolved = MediaCapabilityResolver.resolve(
        provider(capabilities: {'seedance-2.0': declared}),
        'seedance-2.0',
      );
      expect(resolved.durations, [4, 8, 12]);
      expect(resolved.maxReferenceImages, 3);
      expect(resolved.isDeclared, isTrue);
    });

    test('同供应商不同模型各有各的声明', () {
      final capabilities = {
        'model-a': const MediaModelCapability(durations: [4, 8], isDeclared: true),
        'model-b': const MediaModelCapability(durations: [5, 10], isDeclared: true),
      };
      expect(
        MediaCapabilityResolver.resolve(provider(capabilities: capabilities), 'model-a')
            .durations,
        [4, 8],
      );
      expect(
        MediaCapabilityResolver.resolve(provider(capabilities: capabilities), 'model-b')
            .durations,
        [5, 10],
      );
    });
  });

  group('默认回退', () {
    test('openai 协议未声明时取保守默认且 isDeclared=false', () {
      final resolved = MediaCapabilityResolver.resolve(
        provider(protocol: AiProtocolType.openai),
        'unknown-model',
      );
      expect(resolved.isDeclared, isFalse);
      expect(resolved.maxReferenceImages, 1);
      expect(resolved.supportsLastFrame, isFalse);
      expect(resolved.durations, isNotEmpty);
    });

    test('agnes 协议未声明时取 agnes 默认', () {
      final resolved = MediaCapabilityResolver.resolve(
        provider(protocol: AiProtocolType.agnes),
        'unknown-agnes',
      );
      expect(resolved.isDeclared, isFalse);
      // Agnes 的 seconds 只到 12（见 AgnesVideoAdapter 的 clamp）。
      expect(resolved.durations.last, lessThanOrEqualTo(12));
      expect(resolved.supportsFirstFrame, isTrue);
    });

    test('anthropic / gemini 协议给空壳（不参与媒体生成）', () {
      for (final protocol in [AiProtocolType.anthropic, AiProtocolType.gemini]) {
        final resolved = MediaCapabilityResolver.resolve(
          provider(protocol: protocol),
          'any',
        );
        expect(resolved.durations, isEmpty);
        expect(resolved.maxReferenceImages, 0);
        expect(resolved.isDeclared, isFalse);
      }
    });
  });

  group('时长吸附（向下取整）', () {
    const cap = MediaModelCapability(
      durations: [4, 5, 6, 8, 10, 12],
      isDeclared: true,
    );

    test('请求超过上限时落到不超过它的最大值', () {
      expect(cap.snapDuration(15), 12);
      expect(cap.snapDuration(11), 10);
      expect(cap.snapDuration(7), 6);
    });

    test('请求值本身就是合法值时原样返回', () {
      expect(cap.snapDuration(8), 8);
    });

    test('请求小于所有合法值时取最小合法值', () {
      expect(cap.snapDuration(2), 4);
      expect(cap.snapDuration(1), 4);
    });

    test('durations 为空表示不限制', () {
      const any = MediaModelCapability(isDeclared: true);
      expect(any.snapDuration(37), 37);
    });

    test('supportsDuration 对空集合放行', () {
      const any = MediaModelCapability(isDeclared: true);
      expect(any.supportsDuration(999), isTrue);
      expect(cap.supportsDuration(8), isTrue);
      expect(cap.supportsDuration(9), isFalse);
    });
  });

  group('分辨率吸附（按比例距离）', () {
    const cap = MediaModelCapability(
      resolutions: ['480p', '720p', '1080p'],
      isDeclared: true,
    );

    test('白名单里没有时取第一个', () {
      // '1080x1920' 不在 ['480p','720p','1080p'] 里，且都解析不出比例。
      expect(cap.snapResolution('1080x1920', cap.resolutions), '480p');
    });

    test('比例相同时取像素量更接近的', () {
      // 两个候选都是 9:16。比例差打平时像素量决胜：1152x2048 比 864x1536
      // 更接近工坊请求的 1080x1920，出图细节更多。
      final legal = ['864x1536', '1152x2048'];
      expect(cap.snapResolution('1080x1920', legal), '1152x2048');
      // 顺序无关——评分而不是列表位置决定。
      final reversed = ['1152x2048', '864x1536'];
      expect(cap.snapResolution('1080x1920', reversed), '1152x2048');
    });

    test('比例更接近的候选胜出（比例权重高于像素量）', () {
      // 1024x1024 像素量(1M)比 1152x2048(2.3M)更接近 1080x1920(2.1M)，
      // 但比例差 0.44 远大于 0——比例权重 ×10 后仍胜出。
      final legal = ['1024x1024', '1152x2048'];
      expect(cap.snapResolution('1080x1920', legal), '1152x2048');
    });

    test('比例差相同时像素量决胜', () {
      // 1:1 与 4:3 对 9:16 的比例差不同，造一个真正打平的场景：
      // 512x512(0.26M) 与 2048x2048(4.2M) 都是 1:1，请求 1024x1024(1M)。
      final legal = ['512x512', '2048x2048'];
      expect(cap.snapResolution('1024x1024', legal), '512x512');
    });

    test('请求值合法时原样返回', () {
      expect(cap.snapResolution('720p', cap.resolutions), '720p');
    });

    test('合法集合为空时原样返回', () {
      expect(cap.snapResolution('1080p', const []), '1080p');
    });
  });

  group('序列化', () {
    test('往返后字段不丢', () {
      const original = MediaModelCapability(
        modes: {MediaGenMode.text, MediaGenMode.multiReference},
        durations: [4, 8, 12],
        durationResolutions: {
          4: ['480p', '720p'],
          8: ['720p'],
        },
        resolutions: ['720p'],
        ratios: ['9:16', '16:9'],
        maxReferenceImages: 9,
        supportsFirstFrame: true,
        supportsLastFrame: true,
        supportsNativeAudio: true,
        isDeclared: true,
      );
      final restored = MediaModelCapability.fromJson(original.toJson());
      expect(restored.modes, original.modes);
      expect(restored.durations, original.durations);
      expect(restored.durationResolutions, original.durationResolutions);
      expect(restored.resolutions, original.resolutions);
      expect(restored.ratios, original.ratios);
      expect(restored.maxReferenceImages, 9);
      expect(restored.supportsFirstFrame, isTrue);
      expect(restored.supportsLastFrame, isTrue);
      expect(restored.supportsNativeAudio, isTrue);
      expect(restored.isDeclared, isTrue);
    });

    test('resolutionsFor 未按时长区分时回落到通用集合', () {
      const cap = MediaModelCapability(
        durations: [4, 8],
        durationResolutions: {4: ['480p']},
        resolutions: ['720p'],
        isDeclared: true,
      );
      expect(cap.resolutionsFor(4), ['480p']);
      expect(cap.resolutionsFor(8), ['720p']);
    });

    test('MediaGenMode.fromId 对未知值返回 null 而不是抛', () {
      expect(MediaGenMode.fromId('text'), MediaGenMode.text);
      expect(MediaGenMode.fromId('bogus'), isNull);
      expect(MediaGenMode.fromId(null), isNull);
    });
  });

  group('内置声明', () {
    test('Seedance 视频模型的声明与适配器行为一致', () {
      final cap = MediaCapabilityPresets.forModel('doubao-seedance-2-0-260128')!;
      // 适配器 clamp(4, 15) → durations 最大值 15。
      expect(cap.durations.last, 15);
      // 适配器原生支持多参考（content 数组多项 image）。
      expect(cap.maxReferenceImages, greaterThan(1));
      expect(cap.supportsFirstFrame, isTrue);
      expect(cap.isDeclared, isTrue);
    });

    test('Agnes 的 maxReferenceImages 只能是 1（官方禁止混用）', () {
      final cap = MediaCapabilityPresets.forModel('agnes-video-2.5-flash')!;
      expect(cap.maxReferenceImages, 1);
      expect(cap.durations.last, 12);
    });

    test('Dola 免费号池命中三档时长声明', () {
      // 前缀归一：模型 id 由适配器拼成 'dola-pool-$_model'。
      for (final id in const [
        'dola-pool-seedance-2.0',
        'dola-pool-seedance-2.5',
      ]) {
        final cap = MediaCapabilityPresets.forModel(id);
        expect(cap, isNotNull, reason: '$id 应命中内置声明');
        expect(cap!.durations, [5, 10, 15],
            reason: '免费版只接受这三档，多一个都会让上游拒绝');
        expect(cap.isDeclared, isTrue);
      }
    });

    test('Dola 不具备任何图片输入能力', () {
      final cap = MediaCapabilityPresets.forModel('dola-pool-seedance-2.5')!;
      // 请求体只有 text_block。声明 0 而不是 1：声明 1 会让调用方以为
      // 「传一张也行」，然后把首帧塞进没有图片字段的请求里。
      expect(cap.maxReferenceImages, 0);
      expect(cap.supportsFirstFrame, isFalse);
      expect(cap.supportsLastFrame, isFalse);
      expect(cap.modes, {MediaGenMode.text});
    });

    test('Dola 时长吸附两个方向', () {
      final cap = MediaCapabilityPresets.forModel('dola-pool-seedance-2.5')!;
      // 低于下限 → 取最小档（分镜默认 3 秒会走到这条）。
      expect(cap.snapDuration(3), 5);
      // 介于两档之间 → 取不超过请求值的最大档。
      expect(cap.snapDuration(8), 5);
      expect(cap.snapDuration(12), 10);
      expect(cap.snapDuration(14), 10);
      // 超过上限 → 取最大档。
      expect(cap.snapDuration(20), 15);
      expect(cap.snapDuration(30), 15);
    });

    test('Dola 路径下携带参考图被显式拒绝，错误文本说得出原因', () {
      final cap = MediaCapabilityPresets.forModel('dola-pool-seedance-2.5')!;
      // 0 张是合法值（文生视频），1 张就该被拒——拒绝文本必须让用户知道
      // 是引擎不支持，而不是泛泛的「生成失败」。
      expect(
        () => MediaRequestNormalizer(cap).normalize(
          const MediaRequestSpec(
            durationSec: 5,
            referenceImageCount: 1,
          ),
        ),
        throwsA(isA<MediaCapabilityException>().having(
          (e) => e.message,
          'message',
          contains('参考图'),
        )),
      );
    });

    test('Dola 的适配器兜底与能力矩阵意图一致', () {
      // 两层吸附：适配器内的 _snapDuration 是单独使用时的保险，_wrap 的规整
      // 是主路径。两者必须给出同一个值，否则用户会看到相互矛盾的行为。
      final cap = MediaCapabilityPresets.forModel('dola-pool-seedance-2.5')!;
      for (final requested in const [3, 5, 8, 10, 12, 15, 20]) {
        expect(
          DolaPoolVideoAdapter.debugSnapDuration(requested.toDouble()),
          cap.snapDuration(requested),
          reason: '请求 ${requested}s 时两层吸附不一致',
        );
      }
    });

    test('SenseAudio 图像的尺寸白名单与适配器一致', () {
      final cap = MediaCapabilityPresets.forModel('senseaudio-image-2.0-260319')!;
      expect(cap.resolutions, contains('1152x2048'));
      expect(cap.resolutions, contains('864x1536'));
      expect(cap.resolutions.length, greaterThan(10));
    });

    test('未知模型 id 返回 null（调用方走协议默认）', () {
      expect(MediaCapabilityPresets.forModel('some-random-model'), isNull);
    });

    test('解析器在无显式声明时用内置声明', () {
      final resolved = MediaCapabilityResolver.resolve(
        provider(),
        'doubao-seedance-2-0-260128',
      );
      // 走的是内置声明而不是 openai 默认——两者 durations 不同。
      expect(resolved.durations.last, 15);
      expect(resolved.isDeclared, isTrue);
      expect(resolved.maxReferenceImages, greaterThan(1));
    });

    test('显式声明优先于内置声明', () {
      final resolved = MediaCapabilityResolver.resolve(
        provider(capabilities: const {
          'doubao-seedance-2-0-260128': MediaModelCapability(
            durations: [4],
            isDeclared: true,
          ),
        }),
        'doubao-seedance-2-0-260128',
      );
      expect(resolved.durations, [4]);
    });
  });

  group('请求规整', () {
    const cap = MediaModelCapability(
      durations: [4, 5, 6, 8, 10, 12],
      resolutions: ['480p', '720p', '1080p'],
      ratios: ['9:16', '16:9'],
      maxReferenceImages: 2,
      supportsFirstFrame: true,
      supportsLastFrame: false,
      modes: {MediaGenMode.text, MediaGenMode.singleImage},
      isDeclared: true,
    );
    const normalizer = MediaRequestNormalizer(cap);

    test('15s 请求被吸附到 12s 并记录变更', () {
      final result = normalizer.normalize(
        const MediaRequestSpec(durationSec: 15),
      );
      expect(result.request.durationSec, 12);
      expect(result.hasChanges, isTrue);
      expect(result.changes.single, contains('15s → 12s'));
    });

    test('合法参数原样通过且无变更记录', () {
      final result = normalizer.normalize(
        const MediaRequestSpec(durationSec: 8, resolution: '720p', ratio: '9:16'),
      );
      expect(result.request.durationSec, 8);
      expect(result.request.resolution, '720p');
      expect(result.hasChanges, isFalse);
    });

    test('参考图超限被拒绝而不是截断', () {
      expect(
        () => normalizer.normalize(
          const MediaRequestSpec(referenceImageCount: 3),
        ),
        throwsA(
          isA<MediaCapabilityException>().having(
            (e) => e.message,
            'message',
            contains('参考图'),
          ),
        ),
      );
    });

    test('不支持首帧时被拒绝', () {
      const noFirstFrame = MediaModelCapability(
        durations: [4],
        supportsFirstFrame: false,
        isDeclared: true,
      );
      expect(
        () => MediaRequestNormalizer(noFirstFrame).normalize(
          const MediaRequestSpec(hasFirstFrame: true),
        ),
        throwsA(isA<MediaCapabilityException>()),
      );
    });

    test('不支持尾帧时被拒绝', () {
      expect(
        () => normalizer.normalize(const MediaRequestSpec(hasLastFrame: true)),
        throwsA(isA<MediaCapabilityException>()),
      );
    });

    test('模式不在集合内时被拒绝', () {
      expect(
        () => normalizer.normalize(
          const MediaRequestSpec(mode: MediaGenMode.multiReference),
        ),
        throwsA(isA<MediaCapabilityException>()),
      );
    });

    test('模式为 null 时放行（调用方未指定）', () {
      final result = normalizer.normalize(const MediaRequestSpec());
      expect(result.request.mode, isNull);
    });

    test('能力 modes 为空时不过滤模式', () {
      const anyMode = MediaModelCapability(durations: [4], isDeclared: true);
      final result = MediaRequestNormalizer(anyMode).normalize(
        const MediaRequestSpec(mode: MediaGenMode.startEndRequired),
      );
      expect(result.request.mode, MediaGenMode.startEndRequired);
    });

    test('durations 为空时不钳制时长', () {
      const anyDuration = MediaModelCapability(isDeclared: true);
      final result = MediaRequestNormalizer(anyDuration).normalize(
        const MediaRequestSpec(durationSec: 42),
      );
      expect(result.request.durationSec, 42);
    });
  });

  group('AiProviderConfig 序列化', () {
    test('media_capabilities 往返', () {
      final original = AiProviderConfig(
        id: 'p',
        name: 'P',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://x',
        keychainKeyId: 'k',
        mediaCapabilities: const {
          'm1': MediaModelCapability(durations: [4, 8], isDeclared: true),
        },
      );
      final restored = AiProviderConfig.fromJson(original.toJson());
      expect(restored.mediaCapabilities.keys, ['m1']);
      expect(restored.mediaCapabilities['m1']!.durations, [4, 8]);
    });

    test('空 map 不写 media_capabilities 键', () {
      final config = AiProviderConfig(
        id: 'p',
        name: 'P',
        protocol: AiProtocolType.openai,
        baseUrl: 'https://x',
        keychainKeyId: 'k',
      );
      expect(config.toJson().containsKey('media_capabilities'), isFalse);
    });

    test('旧配置文件（无该键）加载后为空 map 不报错', () {
      final legacy = {
        'id': 'p',
        'name': 'P',
        'protocol': 'openai',
        'baseUrl': 'https://x',
        'keychainKeyId': 'k',
        'enabled': true,
        'models': {'text': ['gpt-4']},
      };
      final restored = AiProviderConfig.fromJson(legacy);
      expect(restored.mediaCapabilities, isEmpty);
    });

    test('形状损坏的能力条目被跳过而不是让整个配置加载失败', () {
      final restored = AiProviderConfig.fromJson({
        'id': 'p',
        'protocol': 'openai',
        'media_capabilities': {
          'good': {'durations': [4], 'is_declared': true},
          'bad': 'not-a-map',
          'alsoBad': {'durations': 'nope'},
        },
      });
      // 'good' 正常；'bad' 被跳过；'alsoBad' 形状是 Map 但字段类型不对，
      // fromJson 的宽容解析会返回一个空壳而不是抛。
      expect(restored.mediaCapabilities.containsKey('good'), isTrue);
      expect(restored.mediaCapabilities.containsKey('bad'), isFalse);
    });
  });
}
