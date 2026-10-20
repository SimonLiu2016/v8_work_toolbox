import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../../../services/ai_config_store.dart';
import '../../../../services/ai_service.dart';
import '../../../../services/keychain_service.dart';
import '../../../../services/media_capability.dart';
import '../../ai_video_studio/services/image_gen_adapter.dart';
import '../../ai_video_studio/services/video_gen_adapter.dart';
import '../../ai_video_studio/services/video_task_ledger.dart';
import '../models/playground_models.dart';
import 'playground_store.dart';

/// 试炼场的调用层：收集参数 → 调既有入口 → 落快照。
///
/// **刻意薄**：它不实现任何协议，也不复制任何适配器逻辑。三个通道分别落到
/// `AiService` / 图像适配器 / `AgnesVideoAdapter`——试炼场只负责把"用户填的"
/// 翻译成"适配器要的"，再把结果连同请求一起交给 [PlaygroundStore]。
///
/// 这样做的直接好处：工坊主路径与试炼场共用同一份协议实现，修一次两边同时
/// 受益，不会出现"试炼场能发尾帧但工坊不能"这种分裂。
class PlaygroundService {
  PlaygroundService._();
  static final PlaygroundService instance = PlaygroundService._();

  /// 当前配置里可用的供应商（启用中的）。
  List<AiProviderConfig> availableProviders() {
    return AiConfigStore.instance.providers
        .where((p) => p.enabled)
        .toList(growable: false);
  }

  /// 某供应商在某通道下的候选型号。
  List<String> modelsFor(AiProviderConfig provider, PlaygroundChannel channel) {
    return switch (channel) {
      PlaygroundChannel.text => provider.textModels,
      PlaygroundChannel.image => provider.imageModels,
      PlaygroundChannel.video => provider.videoModels,
    };
  }

  /// 该通道下该型号的能力声明（供参数面板收敛档位与比例）。
  MediaModelCapability capabilityFor(String model) {
    final provider = _findProviderForModel(model);
    return MediaCapabilityResolver.resolve(
      provider ?? _anonymousProvider,
      model,
    );
  }

  AiProviderConfig? _findProviderForModel(String model) {
    for (final p in availableProviders()) {
      final all = [
        ...p.textModels,
        ...p.imageModels,
        ...p.videoModels,
        ...p.multimodalModels,
      ];
      if (all.contains(model)) return p;
    }
    return null;
  }

  /// 找不到供应商时用一个只带协议 id 的视图——能力查找会落到协议级保守默认。
  AiProviderConfig get _anonymousProvider => const AiProviderConfig(
        id: '',
        name: '',
        protocol: AiProtocolType.openai,
        baseUrl: '',
        keychainKeyId: '',
      );

  AiProviderConfig? providerById(String id) {
    for (final p in availableProviders()) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// 执行一轮调用并落快照。
  Future<PlaygroundTurn> submit(PlaygroundDraft draft) async {
    final provider = providerById(draft.providerId) ??
        _findProviderForModel(draft.model) ??
        _anonymousProvider;

    return PlaygroundStore.instance.record(
      channel: draft.channel,
      providerId: provider.id,
      providerName: provider.name.isNotEmpty ? provider.name : '未命名供应商',
      model: draft.model,
      prompt: draft.prompt,
      params: _collectParams(draft),
      media: draft.media,
      invoke: (outputDir) => _invoke(draft, provider, outputDir),
    );
  }

  /// 收集"将要提交"的参数。与快照里的 `params` 同一份，提交前后一致。
  Map<String, String> _collectParams(PlaygroundDraft draft) {
    final params = <String, String>{};
    if (draft.channel == PlaygroundChannel.video) {
      params['mode'] = draft.mode;
      params['seconds'] = '${draft.durationSec}';
      if (draft.sizeTier.trim().isNotEmpty) {
        params['size'] = draft.sizeTier.trim();
      }
      if (draft.ratio.trim().isNotEmpty) {
        params['aspect_ratio'] = draft.ratio.trim();
      }
      if (draft.seed.trim().isNotEmpty) {
        params['seed'] = draft.seed.trim();
      }
    }
    return params;
  }

  Future<PlaygroundCallOutcome> _invoke(
    PlaygroundDraft draft,
    AiProviderConfig provider,
    Directory outputDir,
  ) async {
    switch (draft.channel) {
      case PlaygroundChannel.text:
        return _invokeText(draft, provider, outputDir);
      case PlaygroundChannel.image:
        return _invokeImage(draft, provider, outputDir);
      case PlaygroundChannel.video:
        return _invokeVideo(draft, provider, outputDir);
    }
  }

  // --- 文本通道 -----------------------------------------------------------

  Future<PlaygroundCallOutcome> _invokeText(
    PlaygroundDraft draft,
    AiProviderConfig provider,
    Directory outputDir,
  ) async {
    if (provider.id.isEmpty) {
      return PlaygroundCallOutcome.failure(
        '未找到供应商「${draft.providerId}」的配置，请检查 AI 基础设施设置。',
      );
    }
    try {
      final result = await AiService.instance.chat(
        slot: 'text',
        explicitProviderId: provider.id,
        explicitModel: draft.model,
        messages: [
          {'role': 'user', 'content': draft.prompt},
        ],
      );
      // 文本产物落成 .md：Markdown 在界面里能直接按共享主题渲染，纯 .txt
      // 则要另做一套只读视图。
      final name = 'response.md';
      final file = File('${outputDir.path}/$name');
      await file.writeAsString(result.text, flush: true);
      return PlaygroundCallOutcome(
        status: PlaygroundTurnStatus.completed,
        outputFileName: name,
        outputBytes: await file.length(),
      );
    } catch (e) {
      return PlaygroundCallOutcome.failure(e.toString());
    }
  }

  // --- 图像通道 -----------------------------------------------------------

  Future<PlaygroundCallOutcome> _invokeImage(
    PlaygroundDraft draft,
    AiProviderConfig provider,
    Directory outputDir,
  ) async {
    final key = provider.keychainKeyId.isNotEmpty
        ? await KeychainService.instance.readSecret(provider.keychainKeyId)
        : null;
    if (key == null || key.trim().isEmpty) {
      return PlaygroundCallOutcome.failure(
        '未检测到「${provider.name}」的 API Key，请先在 AI 基础设施配置中保存。',
      );
    }

    final output = File('${outputDir.path}/image.png');
    final adapter = SystemAiImageAdapter(
      baseUrl: provider.baseUrl,
      model: draft.model,
      apiKey: key.trim(),
      providerId: provider.id,
      keychainKeyId: provider.keychainKeyId,
    );

    // 参考图按角色分流：图像模型只有一种图输入通道（extra_body.image），
    // 所以首帧/尾帧标注在这里没有意义——全部作为普通参考图提交，UI 也不
    // 给图像通道显示角色选择。
    final refs = draft.media.map((m) => m.file.path).toList();

    try {
      // 尺寸：从用户的档位与比例反推像素，交给 SystemAiImageAdapter 自己按
      // Agnes 规则规整（它有 resolveAgnesSizeAndRatio）。空档位时用 1080×1920
      // 的竖屏默认——那是工坊的默认画幅。
      final (w, h) = _pixelsFor(draft.sizeTier, draft.ratio);
      await adapter.generate(
        ImageGenRequest(
          prompt: draft.prompt,
          shotNumber: 0,
          outputFile: output,
          width: w,
          height: h,
          referenceImages: refs,
        ),
      );
      if (!await output.exists()) {
        return PlaygroundCallOutcome.failure('图像生成未产出文件');
      }
      return PlaygroundCallOutcome(
        status: PlaygroundTurnStatus.completed,
        outputFileName: 'image.png',
        outputBytes: await output.length(),
      );
    } catch (e) {
      return PlaygroundCallOutcome.failure(e.toString());
    }
  }

  /// 把档位 + 比例换算成像素。只在图像通道用（视频走 Agnes 的档位字符串）。
  static (int, int) _pixelsFor(String sizeTier, String ratio) {
    final base = switch (sizeTier.trim().toLowerCase()) {
      '1k' => 1024,
      '2k' => 2048,
      '3k' => 3072,
      '4k' => 4096,
      _ => 1080,
    };
    return switch (ratio.trim()) {
      '1:1' => (base, base),
      '16:9' => ((base * 16 / 9).round(), base),
      '4:3' => ((base * 4 / 3).round(), base),
      '3:4' => (base, (base * 4 / 3).round()),
      '9:16' => (base, (base * 16 / 9).round()),
      _ => (base, (base * 16 / 9).round()),
    };
  }

  // --- 视频通道 -----------------------------------------------------------

  Future<PlaygroundCallOutcome> _invokeVideo(
    PlaygroundDraft draft,
    AiProviderConfig provider,
    Directory outputDir,
  ) async {
    final key = provider.keychainKeyId.isNotEmpty
        ? await KeychainService.instance.readSecret(provider.keychainKeyId)
        : null;
    if (key == null || key.trim().isEmpty) {
      return PlaygroundCallOutcome.failure(
        '未检测到「${provider.name}」的 API Key，请先在 AI 基础设施配置中保存。',
      );
    }

    File? firstFrame;
    File? lastFrame;
    final refs = <File>[];
    for (final m in draft.media) {
      switch (m.role) {
        case PlaygroundMediaRole.firstFrame:
          firstFrame ??= m.file;
        case PlaygroundMediaRole.lastFrame:
          lastFrame ??= m.file;
        case PlaygroundMediaRole.reference:
          refs.add(m.file);
      }
    }

    final output = File('${outputDir.path}/video.mp4');
    final adapter = AgnesVideoAdapter(
      baseUrl: provider.baseUrl,
      model: draft.model,
      apiKey: key.trim(),
      providerId: provider.id,
      keychainKeyId: provider.keychainKeyId,
    );

    try {
      await adapter.generateVideo(
        VideoGenRequest(
          inputImage: firstFrame,
          lastFrameImage: lastFrame,
          referenceImages: refs,
          promptZh: draft.prompt,
          durationSec: draft.durationSec.toDouble(),
          shotNumber: 0,
          outputFile: output,
          mode: AgnesVideoMode.fromId(draft.mode),
          sizeTier: draft.sizeTier.trim(),
          ratio: draft.ratio.trim(),
          seed: draft.seed.trim().isEmpty ? null : int.tryParse(draft.seed.trim()),
        ),
      );
      if (!await output.exists()) {
        return PlaygroundCallOutcome.failure('视频生成未产出文件');
      }
      return PlaygroundCallOutcome(
        status: PlaygroundTurnStatus.completed,
        outputFileName: 'video.mp4',
        outputBytes: await output.length(),
      );
    } on StateError catch (e) {
      // 「本地等待预算耗尽但云端仍在处理」是可辨识的终态：钱花了、视频还在。
      // 判失败会让用户以为没花钱也没产出——那是比报错更糟的谎。
      final msg = e.message;
      if (msg.contains('云端仍在处理') || msg.contains('video_id')) {
        final videoId = _extractVideoId(msg);
        return PlaygroundCallOutcome(
          status: PlaygroundTurnStatus.cloudProcessing,
          remoteTaskId: videoId,
          error: msg,
        );
      }
      return PlaygroundCallOutcome.failure(msg);
    } catch (e) {
      return PlaygroundCallOutcome.failure(e.toString());
    }
  }

  /// 从错误信息里抠出 video_id。
  ///
  /// 适配器的报错文案形如「……（video_id: video_xxx）」。抠不出来就返回空串
  /// ——宁可没有线索，也不编一个。
  static String _extractVideoId(String message) {
    final match = RegExp(r'video_id[::]\s*([A-Za-z0-9_\-]+)').firstMatch(message);
    return match?.group(1) ?? '';
  }

  /// 对停在「云端处理中」的轮次继续等待。
  ///
  /// 复用适配器的 `resumePolling`——那是恢复路径用的同一个入口，不复制第二份。
  /// 台账条目由适配器内部按 `remoteTaskId` 查；试炼场的轮次只负责把结论
  /// 写回快照。
  Future<bool> resumeCloudTask(PlaygroundTurn turn) async {
    final videoId = turn.remoteTaskId;
    if (videoId.isEmpty) return false;

    final provider = providerById(turn.providerId);
    if (provider == null) return false;
    final key = provider.keychainKeyId.isNotEmpty
        ? await KeychainService.instance.readSecret(provider.keychainKeyId)
        : null;
    if (key == null || key.trim().isEmpty) return false;

    final adapter = AgnesVideoAdapter(
      baseUrl: provider.baseUrl,
      model: turn.model,
      apiKey: key.trim(),
      providerId: provider.id,
      keychainKeyId: provider.keychainKeyId,
    );

    try {
      final entry = await VideoTaskLedger.instance.findByRemoteId(videoId);
      if (entry == null) return false;
      final url = await adapter.resumePolling(entry: entry, onProgress: (_) {});
      if (url == null || url.isEmpty) return false;

      final target = PlaygroundStore.instance.outputFile(turn) ??
          File('${PlaygroundStore.instance.outputDir(turn.id).path}/video.mp4');
      await adapter.downloadTo(url, target);

      await PlaygroundStore.instance.updateTurn(
        turn.id,
        status: PlaygroundTurnStatus.completed,
        outputFileName: 'video.mp4',
        error: null,
      );
      return true;
    } catch (e) {
      debugPrint('[PlaygroundService] 继续等待失败: $e');
      return false;
    }
  }
}
