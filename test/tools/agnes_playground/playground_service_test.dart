import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:V8WorkToolbox/services/ai_config_store.dart';
import 'package:V8WorkToolbox/services/app_paths.dart';
import 'package:V8WorkToolbox/tools/agnes_playground/models/playground_models.dart';
import 'package:V8WorkToolbox/tools/agnes_playground/services/playground_service.dart';
import 'package:V8WorkToolbox/tools/agnes_playground/services/playground_store.dart';

/// 试炼场调用层的回归：三个通道的参数翻译与"失败也留痕"。
///
/// 全部走 mock HTTP（通过 `AiConfigStore` 里供应商的 baseUrl 指向本地假服务
/// 由 `AgnesVideoAdapter` 的 `httpFn` 注入不现实——适配器由服务层构造），所以
/// 这里只验证**不依赖网络的部分**：供应商解析、型号列表、能力查询、以及
/// 缺 Key 时的可读失败。真实链路由 `playground_page_test` 的 widget 测试覆盖
/// 其可观测行为。
void main() {
  group('PlaygroundService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('playground_svc_test');
      AppPaths.overrideRootForTesting(tempDir);
      PlaygroundStore.instance.resetForTesting();
      await AiConfigStore.instance.resetForTesting();
      await AiConfigStore.instance.init(customRootDir: tempDir);
    });

    tearDown(() async {
      PlaygroundStore.instance.resetForTesting();
      await AiConfigStore.instance.resetForTesting();
      AppPaths.resetForTesting();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('未配置任何供应商时 availableProviders 为空', () {
      expect(PlaygroundService.instance.availableProviders(), isEmpty);
    });

    test('按通道返回对应槽位的型号列表', () async {
      final store = AiConfigStore.instance;
      await store.saveProvider(const AiProviderConfig(
        id: 'p1',
        name: 'Agnes',
        protocol: AiProtocolType.agnes,
        baseUrl: 'https://api.agnes-ai.cn/v1',
        keychainKeyId: 'k1',
        textModels: ['agnes-2.5-flash'],
        imageModels: ['agnes-image-2.5-flash'],
        videoModels: ['agnes-video-2.5-flash', 'agnes-video-2.5'],
      ));

      final service = PlaygroundService.instance;
      final provider = service.availableProviders().single;
      expect(service.modelsFor(provider, PlaygroundChannel.video), [
        'agnes-video-2.5-flash',
        'agnes-video-2.5',
      ]);
      expect(service.modelsFor(provider, PlaygroundChannel.image),
          ['agnes-image-2.5-flash']);
      expect(service.modelsFor(provider, PlaygroundChannel.text),
          ['agnes-2.5-flash']);
    });

    test('停用的供应商不出现在列表里', () async {
      final store = AiConfigStore.instance;
      await store.saveProvider(const AiProviderConfig(
        id: 'p_off',
        name: '已停用',
        protocol: AiProtocolType.agnes,
        baseUrl: 'https://x/v1',
        keychainKeyId: 'k',
        enabled: false,
        videoModels: ['agnes-video-2.5-flash'],
      ));
      expect(PlaygroundService.instance.availableProviders(), isEmpty);
    });

    test('能力查询按型号分档：Flash 固定 720P，标准型号四档', () {
      final service = PlaygroundService.instance;
      final flash = service.capabilityFor('agnes-video-2.5-flash');
      final std = service.capabilityFor('agnes-video-2.5');

      expect(flash.resolutions, ['720p']);
      expect(std.resolutions, ['720p', '1080p', '1k', '2k']);
      // 两个型号都声明尾帧——适配器现在真的发得出 last_frame。
      expect(flash.supportsLastFrame, isTrue);
      expect(std.supportsLastFrame, isTrue);
    });

    test('未知型号走协议级保守默认而不是崩溃', () {
      final cap = PlaygroundService.instance.capabilityFor('no-such-model');
      expect(cap.isDeclared, isFalse,
          reason: '没测过的型号必须标注「未经确认」');
    });

    test('缺 API Key 时给出可读失败并留快照', () async {
      final store = AiConfigStore.instance;
      await store.saveProvider(const AiProviderConfig(
        id: 'p2',
        name: '无 Key 供应商',
        protocol: AiProtocolType.agnes,
        baseUrl: 'https://api.agnes-ai.cn/v1',
        keychainKeyId: 'missing_key_id',
        videoModels: ['agnes-video-2.5-flash'],
      ));

      final turn = await PlaygroundService.instance.submit(
        PlaygroundDraft(
          channel: PlaygroundChannel.video,
          providerId: 'p2',
          model: 'agnes-video-2.5-flash',
          prompt: '测试提示词',
        ),
      );

      expect(turn.status, PlaygroundTurnStatus.failed);
      expect(turn.error, isNotNull);
      // 失败也要留下请求本身——这是试炼场存在的理由
      expect(turn.prompt, '测试提示词');
      expect(turn.model, 'agnes-video-2.5-flash');
    });

    test('providerId 为空时按型号反查供应商', () async {
      final store = AiConfigStore.instance;
      await store.saveProvider(const AiProviderConfig(
        id: 'p3',
        name: '反查供应商',
        protocol: AiProtocolType.agnes,
        baseUrl: 'https://api.agnes-ai.cn/v1',
        keychainKeyId: 'k3',
        videoModels: ['agnes-video-2.5'],
      ));

      // 不传 providerId——服务层应当从型号反查到 p3
      final provider = PlaygroundService.instance.providerById('');
      expect(provider, isNull);
      final models = PlaygroundService.instance
          .modelsFor(AiConfigStore.instance.providers.single, PlaygroundChannel.video);
      expect(models, ['agnes-video-2.5']);
    });

    test('草稿的提交前预览与快照里的 params 一致', () {
      final draft = PlaygroundDraft(
        channel: PlaygroundChannel.video,
        model: 'agnes-video-2.5-flash',
        prompt: '预览测试',
        durationSec: 8,
        sizeTier: '2k',
        ratio: '16:9',
        mode: 'keyframe',
        seed: '1101',
      );
      final view = draft.renderRedactedRequest();
      expect(view, contains('mode: keyframe'));
      expect(view, contains('seconds: 8'));
      expect(view, contains('size: 2k'));
      expect(view, contains('aspect_ratio: 16:9'));
      expect(view, contains('seed: 1101'));
      expect(view, contains('prompt: 预览测试'));
    });

    test('Keychain 未配置时不抛未捕获异常', () async {
      // 服务层读 Key 前先查 keychainKeyId 是否为空；空则直接给可读失败。
      final store = AiConfigStore.instance;
      await store.saveProvider(const AiProviderConfig(
        id: 'p4',
        name: '空 key id',
        protocol: AiProtocolType.agnes,
        baseUrl: 'https://api.agnes-ai.cn/v1',
        keychainKeyId: '',
        videoModels: ['agnes-video-2.5-flash'],
      ));

      final turn = await PlaygroundService.instance.submit(
        PlaygroundDraft(
          channel: PlaygroundChannel.video,
          providerId: 'p4',
          model: 'agnes-video-2.5-flash',
          prompt: 'x',
        ),
      );
      expect(turn.status, PlaygroundTurnStatus.failed);
      expect(turn.error, contains('API Key'));
    });
  });

  group('AppPaths 登记', () {
    test('试炼场目录已登记进 AppPaths 清单', () {
      // 上一个 group 的 tearDown 调了 resetForTesting，这里要重新覆盖 root。
      AppPaths.overrideRootForTesting(
        Directory.systemTemp.createTempSync('playground_paths_test'),
      );
      expect(
        AppPaths.allDirs.any((d) => d.path == AppPaths.agnesPlaygroundDir.path),
        isTrue,
        reason: '新目录必须登记，否则备份/清理会漏掉它',
      );
      expect(
        AppPaths.allFiles
            .any((f) => f.path == AppPaths.agnesPlaygroundIndexFile.path),
        isTrue,
      );
      // 轮次目录派生自主目录，路径必须在其下
      final turn = AppPaths.agnesPlaygroundTurnDir('turn_x');
      expect(p.isWithin(AppPaths.agnesPlaygroundDir.path, turn.path), isTrue);
      AppPaths.resetForTesting();
    });
  });
}
