import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/media_capability.dart';
import 'package:V8WorkToolbox/tools/dola_pool/services/dola_config_store.dart';
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

    test('Agnes Flash 的参考图上限与型号限制一致', () {
      final cap = MediaCapabilityPresets.forModel('agnes-video-2.5-flash')!;
      expect(cap.maxReferenceImages, 5);
      expect(cap.durations.last, 12);
      // Flash 只支持 720P——传其他档位 Agnes 直接 400。
      expect(cap.resolutions, ['720p']);
    });

    test('Agnes 标准型号支持四档分辨率与更多参考图', () {
      final cap = MediaCapabilityPresets.forModel('agnes-video-2.5')!;
      expect(cap.maxReferenceImages, 8);
      expect(cap.resolutions, ['720p', '1080p', '1k', '2k']);
      expect(cap.supportsLastFrame, isTrue);
    });

    test('Agnes 视频两型号的画幅比例覆盖官方六种白名单', () {
      // 文档的 aspect_ratio 白名单是六种。以前只列五种、缺 21:9，而适配器
      // 又把 aspect_ratio 写死 9:16——两边一起把超宽屏挡在外面。
      const expected = ['9:16', '16:9', '1:1', '4:3', '3:4', '21:9'];
      for (final id in ['agnes-video-2.5', 'agnes-video-2.5-flash']) {
        final cap = MediaCapabilityPresets.forModel(id)!;
        expect(cap.ratios, expected, reason: '$id 的画幅集合应与官方白名单一致');
      }
    });

    test('Agnes 尾帧能力与适配器可达性一致', () {
      // 声明 supportsLastFrame 就必须真的发得出 last_frame——以前声明了
      // 但 VideoGenRequest 与 payload 都没有这个字段（spec: 能力声明描述
      // 真实可达的能力）。
      for (final id in ['agnes-video-2.5', 'agnes-video-2.5-flash']) {
        final cap = MediaCapabilityPresets.forModel(id)!;
        expect(cap.supportsLastFrame, isTrue, reason: '$id 应声明支持尾帧');
        expect(cap.supportsFirstFrame, isTrue, reason: '$id 应声明支持首帧');
      }
      // 适配器侧的可达性由 test/ai_video_studio_adapter_test.dart 的
      // 「Agnes 视频模式三态与参数化」组用 payload 断言覆盖，这里不重复。
    });

    test('supportsNativeAudio 描述输出而非音频参考输入', () {
      // Agnes 的 audios[] 是 reference 模式的输入参考，与"输出是否带音轨"
      // 无关。两个字段曾经被混为一谈，导致有人想靠翻这个布尔判断能否传音频。
      final cap = MediaCapabilityPresets.forModel('agnes-video-2.5')!;
      expect(cap.supportsNativeAudio, isFalse,
          reason: '输出不带原生音轨；音频参考由 reference 模式与参考数上限表达');
      expect(cap.modes, contains(MediaGenMode.multiReference));
    });

    test('Dola 免费号池按型号命中不同的时长集合', () {
      // 前缀归一到具体型号：2.5 是 5/10（30 秒需拼接，未实现故不声明），
      // 2.0 是 5/10/15。合并成一个集合会让其中一个拿到错误的值。
      final cap25 = MediaCapabilityPresets.forModel('dola-pool-seedance-2.5');
      expect(cap25, isNotNull, reason: '2.5 应命中内置声明');
      expect(cap25!.durations, [5, 10]);
      expect(cap25.isDeclared, isTrue);

      final cap20 = MediaCapabilityPresets.forModel('dola-pool-seedance-2.0');
      expect(cap20, isNotNull, reason: '2.0 应命中内置声明');
      expect(cap20!.durations, [5, 10, 15]);
    });

    test('Dola 30 秒档位暂不声明（拼接未实现）', () {
      // 上游 seedance-2.5 支持 5/10/30，但 30 秒走两段 15 秒 + FFmpeg 拼接，
      // 适配器尚未实现。声明一个必然抛错的值比不声明更让用户困惑——他会按
      // 30 秒规划分镜，提交时才知道不行。
      //
      // 这条测试现在是"通过"状态，但它标记的是一个已知缺口：等拼接实现后，
      // 应把 30 加进 dolaVideo25.durations 并同步改这里。
      final cap = MediaCapabilityPresets.forModel('dola-pool-seedance-2.5')!;
      expect(cap.durations, isNot(contains(30)),
          reason: '30 秒档位依赖片段拼接，实现后再开放');
    });

    test('Dola 参考图上限为 null（没测过，不编数字）', () {
      final cap = MediaCapabilityPresets.forModel('dola-pool-seedance-2.5')!;
      // 上游文档说 10 张，但我们没实测、也不做上线控制。用 null 表达
      // 「没测过」而不是 0——0 会让 UI 显示"不支持参考图"这句假话，
      // 用户于是根本不用 Dola 做片段级生成。
      expect(cap.maxReferenceImages, isNull);
      expect(cap.supportsFirstFrame, isTrue,
          reason: '上游确实支持首帧，能力矩阵不该替它说不支持');
      expect(cap.modes, contains(MediaGenMode.multiReference));
    });

    test('null 上限放行任意数量的参考图', () {
      final cap = MediaCapabilityPresets.forModel('dola-pool-seedance-2.5')!;
      // 12 张远超上游文档的 10 张——null 的语义是"没测过"而非"无限"，
      // 所以这里放行；真要在意就在 UI 上配一个上限。
      expect(
        () => MediaRequestNormalizer(cap).normalize(
          const MediaRequestSpec(durationSec: 5, referenceImageCount: 12),
        ),
        returnsNormally,
      );
    });

    test('号池覆盖优先于内置预设（三层优先级第二层）', () async {
      // 优先级：用户覆盖 > 内置预设 > 协议保守默认。这里验前两层。
      final tempDir = await Directory.systemTemp.createTemp('dola_cfg_');
      AppPaths.overrideRootForTesting(tempDir);
      try {
        final store = DolaConfigStore.instance;
        store.resetForTesting();
        await store.init();

        // 未覆盖时拿内置预设。
        expect(
          store.mediaCapabilities.containsKey('dola-pool-seedance-2.5'),
          isFalse,
          reason: '初始状态不该有覆盖',
        );

        // 用户把 2.5 的时长收窄成 5/10（内置是 5/10，改成只留 5）。
        await store.save(
          'dola-pool-seedance-2.5',
          const MediaModelCapability(durations: [5], isDeclared: true),
        );

        // 经 resolver 走一遍，确认覆盖生效。
        final resolved = MediaCapabilityResolver.resolve(
          store,
          'dola-pool-seedance-2.5',
        );
        expect(resolved.durations, [5], reason: '用户覆盖必须优先于内置预设');

        // 删掉覆盖后回落到内置预设。
        await store.save('dola-pool-seedance-2.5', null);
        final restored = MediaCapabilityResolver.resolve(
          store,
          'dola-pool-seedance-2.5',
        );
        expect(restored.durations, [5, 10], reason: '删除覆盖应回落内置预设');
      } finally {
        DolaConfigStore.instance.resetForTesting();
        AppPaths.resetForTesting();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('未知 dola 型号回落而非误命中', () {
      // 将来 _model 换成 seedance-3.0 时，不该拿到 2.5 的声明——
      // 那会让用户以为限制被确认过。应回落协议默认并显示「未经确认」。
      expect(MediaCapabilityPresets.forModel('dola-pool-seedance-3.0'), isNull);
    });

    test('Dola 的适配器兜底与能力矩阵意图一致（两型号）', () {
      // 两层吸附：适配器内的 _snapDuration 是单独使用时的保险，_wrap 的规整
      // 是主路径。两者必须给出同一个值，否则用户会看到相互矛盾的行为。
      // 按型号分别比对——2.5 不含 15 秒，2.0 含，合并比会让其中一个假红。
      for (final (id, model) in const [
        ('dola-pool-seedance-2.5', 'seedance-2.5'),
        ('dola-pool-seedance-2.0', 'seedance-2.0'),
      ]) {
        final cap = MediaCapabilityPresets.forModel(id)!;
        for (final requested in const [3, 5, 8, 10, 12, 15, 20]) {
          expect(
            DolaPoolVideoAdapter.debugSnapDuration(
              requested.toDouble(),
              model: model,
            ),
            cap.snapDuration(requested),
            reason: '$model 请求 ${requested}s 时两层吸附不一致',
          );
        }
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

  group('Agnes 视频模型能力上限与历史配置自愈', () {
    test('MediaCapabilityDefaults.agnes 默认 maxReferenceImages 为 8', () {
      expect(MediaCapabilityDefaults.agnes.maxReferenceImages, 8);
      expect(MediaCapabilityDefaults.agnes.modes, contains(MediaGenMode.multiReference));
    });

    test('agnesVideo25 与 agnesVideo25Flash 官方预设 maxReferenceImages 分别为 8 与 5', () {
      expect(MediaCapabilityPresets.agnesVideo25.maxReferenceImages, 8);
      expect(MediaCapabilityPresets.agnesVideo25Flash.maxReferenceImages, 5);
      expect(MediaCapabilityPresets.agnesVideo25Flash.modes, contains(MediaGenMode.multiReference));
    });

    test('历史旧配置 maxReferenceImages: 1 在 resolve 时自愈升格为预设上限', () {
      final oldDeclared = const MediaModelCapability(
        durations: [4, 5, 6, 8, 10, 12],
        resolutions: ['720p'],
        ratios: ['9:16', '16:9'],
        maxReferenceImages: 1, // 历史配置残留
        supportsFirstFrame: true,
        isDeclared: true,
      );

      final p = provider(
        protocol: AiProtocolType.agnes,
        capabilities: {
          'agnes-video-2.5': oldDeclared,
          'agnes-video-2.5-flash': oldDeclared,
        },
      );

      final resolvedStandard = MediaCapabilityResolver.resolve(p, 'agnes-video-2.5');
      expect(resolvedStandard.maxReferenceImages, 8);
      expect(resolvedStandard.modes, contains(MediaGenMode.multiReference));

      final resolvedFlash = MediaCapabilityResolver.resolve(p, 'agnes-video-2.5-flash');
      expect(resolvedFlash.maxReferenceImages, 5);
      expect(resolvedFlash.modes, contains(MediaGenMode.multiReference));
    });

    test('携带 4 到 8 张参考图的大段请求规整正常通过，超过上限时抛出 MediaCapabilityException', () {
      final oldDeclared = const MediaModelCapability(
        durations: [4, 5, 6, 8, 10, 12],
        resolutions: ['720p'],
        ratios: ['9:16', '16:9'],
        maxReferenceImages: 1,
        supportsFirstFrame: true,
        isDeclared: true,
      );

      final p = provider(
        protocol: AiProtocolType.agnes,
        capabilities: {'agnes-video-2.5': oldDeclared},
      );

      final capability = MediaCapabilityResolver.resolve(p, 'agnes-video-2.5');
      final normalizer = MediaRequestNormalizer(capability);

      // 4 张参考图（用户场景）：通过
      final result4 = normalizer.normalize(
        const MediaRequestSpec(
          durationSec: 8,
          resolution: '720p',
          ratio: '9:16',
          referenceImageCount: 4,
          mode: MediaGenMode.multiReference,
        ),
      );
      expect(result4.request.durationSec, 8);

      // 8 张参考图：通过
      final result8 = normalizer.normalize(
        const MediaRequestSpec(
          durationSec: 8,
          resolution: '720p',
          ratio: '9:16',
          referenceImageCount: 8,
          mode: MediaGenMode.multiReference,
        ),
      );
      expect(result8.request.durationSec, 8);

      // 超过 8 张（如 9 张）：拒绝抛异常
      expect(
        () => normalizer.normalize(
          const MediaRequestSpec(
            durationSec: 8,
            resolution: '720p',
            ratio: '9:16',
            referenceImageCount: 9,
            mode: MediaGenMode.multiReference,
          ),
        ),
        throwsA(isA<MediaCapabilityException>()),
      );
    });
  });

  group('图像模型负向提示词支持声明', () {
    test('默认能力声明 supportsNegativePrompt 为 true', () {
      const cap = MediaModelCapability();
      expect(cap.supportsNegativePrompt, isTrue);
    });

    test('agnesImage 显式声明 supportsNegativePrompt 为 false', () {
      expect(MediaCapabilityPresets.agnesImage.supportsNegativePrompt, isFalse);
    });

    test('解析 agnes-image-2.0/2.1/2.5-flash 型号时命中 supportsNegativePrompt: false', () {
      for (final model in [
        'agnes-image-2.0-flash',
        'agnes-image-2.1-flash',
        'agnes-image-2.5-flash',
      ]) {
        final cap = MediaCapabilityPresets.forModel(model);
        expect(cap, isNotNull);
        expect(cap!.supportsNegativePrompt, isFalse, reason: '$model 应不支持负向词');
      }
    });

    test('MediaModelCapability 序列化与反序列化保留 supports_negative_prompt 字段', () {
      const original = MediaModelCapability(supportsNegativePrompt: false, isDeclared: true);
      final json = original.toJson();
      expect(json['supports_negative_prompt'], isFalse);
      final restored = MediaModelCapability.fromJson(json);
      expect(restored.supportsNegativePrompt, isFalse);
    });
  });
}
