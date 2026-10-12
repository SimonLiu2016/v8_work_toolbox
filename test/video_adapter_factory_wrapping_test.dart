import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/services/keychain_service.dart';
import 'package:V8WorkToolbox/services/media_capability.dart';
import 'package:V8WorkToolbox/tools/dola_pool/services/dola_config_store.dart';
import 'package:V8WorkToolbox/tools/ai_video_studio/services/video_gen_adapter.dart';
import 'package:V8WorkToolbox/tools/password/crypto/kek_manager.dart';

/// 测试用内存 Keychain 桥（flutter test 无平台通道，真实 Keychain 不可用）
class _TestKeychainBridge implements KeychainBridge {
  static final Map<String, String> store = {};

  @override
  Future<String?> read({required String service, required String account}) async {
    return store['$service/$account'];
  }

  @override
  Future<void> write({
    required String service,
    required String account,
    required String value,
  }) async {
    store['$service/$account'] = value;
  }

  @override
  Future<void> delete({required String service, required String account}) async {
    store.remove('$service/$account');
  }
}

/// 取出包装器内部的能力声明，供断言「配置层是否接上」。
List<int> wrapperCapabilityDurations(VideoGenAdapter adapter) {
  final wrapper = adapter as NormalizingVideoAdapter;
  return wrapper.debugCapabilityForTesting.durations;
}

/// `create()` 的返回路径必须全部经过能力规整（spec: 请求参数规整）。
///
/// 这条测试的存在理由写在 `NormalizingVideoAdapter` 的注释里：漏一次规整的
/// bug「只在特定模型上出现，测试很难覆盖到」。漏洞曾出现在工厂侧而非适配器
/// 侧——系统 video 槽位、drama 回退、Dola 免费号池三条路径返回裸适配器，
/// 而系统槽位正是日常最常走的路。
///
/// 因此这里不测规整规则本身（那在 media_capability_matrix_test.dart），只测
/// **每条路径都不返回裸适配器**。改动前触发系统槽位那条是红的——它断言的
/// 正是缺失的东西。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('v8_factory_wrap_');
    AppPaths.overrideRootForTesting(tempDir);
    _TestKeychainBridge.store.clear();
    KeychainService.instance.setKekManagerForTesting(
      KekManager(bridge: _TestKeychainBridge()),
    );
    await AiConfigStore.instance.init(customRootDir: tempDir);
    // 清掉可能的既有槽位绑定，让每条路径的触发条件可控。
    // 目录此时一定存在（上一轮 tearDown 才删），落盘不会失败。
    await AiConfigStore.instance.setSlotBinding('video', '', '');
  });

  tearDown(() async {
    // 顺序：先删目录，再复位 AppPaths。反序会让随后的 setSlotBinding 往已
    // 删除的临时目录写一次，刷一层「保存 ai_config.json 失败」的噪声日志。
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
    AppPaths.resetForTesting();
  });

  /// 造一个已启用、带密钥的供应商并绑到 video 槽位。
  Future<void> seedVideoSlot({
    required String providerId,
    required String model,
    String baseUrl = 'https://api.example.com',
    Map<String, MediaModelCapability> capabilities = const {},
  }) async {
    await AiConfigStore.instance.saveProvider(
      AiProviderConfig(
        id: providerId,
        name: providerId,
        protocol: AiProtocolType.openai,
        baseUrl: baseUrl,
        keychainKeyId: 'k_$providerId',
        videoModels: <String>[model],
        mediaCapabilities: capabilities,
      ),
    );
    await KeychainService.instance.writeSecret('k_$providerId', 'sk-test');
    await AiConfigStore.instance.addSlotCandidate('video', providerId, model);
  }

  group('create() 的返回路径都经过规整', () {
    test('系统 video 槽位（SenseAudio 形状）返回规整包装', () async {
      await seedVideoSlot(providerId: 'p_sense', model: 'doubao-seedance-2-0');

      final adapter = await VideoGenAdapterFactory.create();

      expect(adapter, isA<NormalizingVideoAdapter>(),
          reason: '系统槽位是日常最常走的路径，漏规整影响面最大');
    });

    test('系统 video 槽位（Agnes 形状）返回规整包装', () async {
      // Agnes 分支靠模型名或 baseUrl 判定，走的是同一循环里的另一条 return。
      await seedVideoSlot(
        providerId: 'p_agnes',
        model: 'agnes-video-2.5-flash',
        baseUrl: 'https://api.agnes.example.com',
      );

      final adapter = await VideoGenAdapterFactory.create();

      expect(adapter, isA<NormalizingVideoAdapter>());
    });

    test('显式 preferredEngineId 仍返回规整包装', () async {
      // 这条路径本来就包着，作为对照留在组里：将来谁把它改成裸返回，
      // 组内其它用例的红绿就失去了参照。
      final adapter = await VideoGenAdapterFactory.create(
        preferredEngineId: 'dola-pool-2.5',
      );

      expect(adapter, isA<NormalizingVideoAdapter>());
      // Dola 的 id 形如 dola-pool-seedance-2.5，必须作为 modelId 传进去，
      // 否则能力查找会落到协议保守默认。
      final wrapper = adapter as NormalizingVideoAdapter;
      expect(wrapper.modelId, startsWith('dola-pool-'));
    });

    test('显式选中号池时同样接上能力配置层', () async {
      // 用户改的覆盖必须在「显式选中」这条路上也生效。曾只有回退那条路传了
      // DolaConfigStore，显式选中时配置被静默忽略。
      //
      // 只断言解析到的 capability，不跑 generateVideo——那会真去打 Dola 网络。
      final tempDir = await Directory.systemTemp.createTemp('dola_wrap_');
      AppPaths.overrideRootForTesting(tempDir);
      try {
        await DolaConfigStore.instance.init();
        await DolaConfigStore.instance.save(
          'dola-pool-seedance-2.5',
          const MediaModelCapability(durations: [5], isDeclared: true),
        );

        final adapter = await VideoGenAdapterFactory.create(
          preferredEngineId: 'dola-pool-2.5',
        );
        // 覆盖把合法集合收窄成 [5]；若配置层没接上，这里会是内置预设的 [5, 10]。
        expect(
          wrapperCapabilityDurations(adapter),
          [5],
          reason: '显式选中号池时必须读到用户的覆盖',
        );
      } finally {
        DolaConfigStore.instance.resetForTesting();
        AppPaths.resetForTesting();
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    test('本地 Ken Burns 不包装，且这是有意排除', () async {
      // 没有槽位、productionType 非 drama、Dola 不可用 → 回落到本地 Ken Burns。
      // 它的上界来自 totalFrames.clamp(30, 900)，不该被媒体模型能力矩阵裁剪。
      final adapter = await VideoGenAdapterFactory.create(
        preferredEngineId: 'local-kenburns-ffmpeg',
        productionType: 'anime',
      );

      expect(adapter, isA<KenBurnsVideoAdapter>(),
          reason: '这条排除是设计意图，测试把它写成显式契约，'
              '防止后来者误当漏包「修好」它');
    });
  });
}
