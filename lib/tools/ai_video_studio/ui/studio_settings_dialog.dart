/// 工坊设置：三种能力各自的引擎选择 + API Key + 可用性测试。
///
/// spec 15.1-15.3。API Key 走 [KeychainService]（spec 15.2），与密码库同一
/// 套凭证容器——它们本来就是同一类机密，分开存只会让用户怀疑哪个才是真的。
library;

import 'package:flutter/material.dart';

import '../../../components/app_components.dart';
import '../../../services/keychain_service.dart';
import '../../../shell/ai_config_page.dart';
import '../../../theme/app_theme.dart';
import '../services/image_gen_adapter.dart';
import '../services/video_gen_adapter.dart';

/// 能力类型：图像 / 视频 / TTS。
enum StudioCapability {
  image('image', '图像生成'),
  video('video', '视频生成');

  final String id;
  final String label;

  const StudioCapability(this.id, this.label);
}

/// 一项能力配置。
class CapabilitySetting {
  final String engineId;
  final String apiKey;

  const CapabilitySetting({required this.engineId, required this.apiKey});
}

class StudioSettingsDialog extends StatefulWidget {
  const StudioSettingsDialog({super.key});

  @override
  State<StudioSettingsDialog> createState() => _StudioSettingsDialogState();
}

class _StudioSettingsDialogState extends State<StudioSettingsDialog> {
  final Map<String, TextEditingController> _keys = {};
  final Map<String, String> _engines = {
    StudioCapability.image.id: 'system-image',
    StudioCapability.video.id: 'system-video',
  };
  final Map<String, String> _testResult = {};
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    for (final capability in StudioCapability.values) {
      final engineId = _engines[capability.id]!;
      final keyId = _keychainIdFor(engineId);
      final key = keyId == null
          ? null
          : await KeychainService.instance.readSecret(keyId);
      _keys[capability.id] = TextEditingController(text: key ?? '');
    }
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  @override
  void dispose() {
    for (final c in _keys.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String? _keychainIdFor(String engineId) {
    return switch (engineId) {
      'siliconflow-flux-schnell' => SiliconFlowImageAdapter.keychainKeyId,
      'kling-i2v' => KlingVideoAdapter.keychainKeyId,
      _ => null,
    };
  }

  void _openAiConfig() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (navCtx) => Scaffold(
          appBar: AppBar(
            title: const Text('AI 基础设施配置'),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(navCtx).pop(),
            ),
          ),
          body: const AiConfigPage(),
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _testResult.remove(StudioCapability.image.id);
        _testResult.remove(StudioCapability.video.id);
      });
    }
  }

  Future<void> _save(StudioCapability capability) async {
    final engineId = _engines[capability.id]!;
    if (engineId == 'system-image' ||
        engineId == 'system-video' ||
        engineId == 'local-kenburns-ffmpeg' ||
        engineId == 'local-stub') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${capability.label} 引擎设置已应用')),
      );
      return;
    }
    final keyId = _keychainIdFor(engineId);
    if (keyId == null) return;
    final value = _keys[capability.id]!.text.trim();
    if (value.isEmpty) {
      await KeychainService.instance.deleteSecret(keyId);
    } else {
      await KeychainService.instance.writeSecret(keyId, value);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${capability.label} 配置已保存')),
    );
  }

  Future<void> _test(StudioCapability capability) async {
    if (!mounted) return;
    setState(() => _testResult[capability.id] = 'testing');
    final engineId = _engines[capability.id]!;
    try {
      final ok = switch (engineId) {
        'system-image' => await (await ImageGenAdapterFactory.create(
            preferredEngineId: 'system-image',
          )).isAvailable(),
        'local-stub' => await const LocalStubImageAdapter().isAvailable(),
        'siliconflow-flux-schnell' =>
          await SiliconFlowImageAdapter().isAvailable(),
        'local-kenburns-ffmpeg' => await KenBurnsVideoAdapter().isAvailable(),
        'kling-i2v' => await KlingVideoAdapter().isAvailable(),
        'system-video' => await (await VideoGenAdapterFactory.create(
            preferredEngineId: 'system-video',
          )).isAvailable(),
        _ => false,
      };
      if (!mounted) return;
      setState(() => _testResult[capability.id] = ok ? 'pass' : 'fail');
    } catch (e) {
      if (!mounted) return;
      setState(() => _testResult[capability.id] = 'fail');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: context.bgCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: 560,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 20, color: context.accentText),
                const SizedBox(width: 8),
                Text(
                  '工坊模型与引擎设置',
                  style: TextStyle(
                    color: context.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '可跟随系统全局 AI 基础设施中配置的模型（推荐），亦可针对工坊选用本地动效或独立 API Key。',
              style: TextStyle(color: context.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 20),
            if (!_loaded)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              for (final capability in StudioCapability.values)
                _CapabilitySection(
                  title: capability.label,
                  engineId: _engines[capability.id]!,
                  engines: _enginesFor(capability),
                  keyController: _keys[capability.id]!,
                  testResult: _testResult[capability.id],
                  onEngineChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _engines[capability.id] = value;
                      _testResult.remove(capability.id);
                    });
                  },
                  onSave: () => _save(capability),
                  onTest: () => _test(capability),
                  onOpenAiConfig: _openAiConfig,
                ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: AppButton.secondary(
                label: '完成并关闭',
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<({String id, String label, bool needsKey})> _enginesFor(
    StudioCapability capability,
  ) {
    switch (capability) {
      case StudioCapability.image:
        final summary = ImageGenAdapterFactory.getSystemImageConfigSummary();
        final systemLabel = summary.isConfigured
            ? '🌟 跟随系统配置 (${summary.description})'
            : '🌟 跟随系统配置 (未绑定图像模型)';
        return [
          (id: 'system-image', label: systemLabel, needsKey: false),
          (id: 'local-stub', label: '本地占位图（免费）', needsKey: false),
          (
            id: 'siliconflow-flux-schnell',
            label: '硅基流动 Flux-schnell（每日免费额度）',
            needsKey: true,
          ),
        ];
      case StudioCapability.video:
        final summary = VideoGenAdapterFactory.getSystemVideoConfigSummary();
        final systemLabel = summary.isConfigured
            ? '🌟 跟随系统配置 (${summary.description})'
            : '🌟 跟随系统配置 (未绑定视频模型)';
        return [
          (id: 'system-video', label: systemLabel, needsKey: false),
          (
            id: 'local-kenburns-ffmpeg',
            label: '本地 Ken Burns 动效（FFmpeg，免费）',
            needsKey: false,
          ),
          (id: 'kling-i2v', label: '可灵 Kling 图生视频（独立配置）', needsKey: true),
        ];
    }
  }
}

class _CapabilitySection extends StatelessWidget {
  const _CapabilitySection({
    required this.title,
    required this.engineId,
    required this.engines,
    required this.keyController,
    required this.testResult,
    required this.onEngineChanged,
    required this.onSave,
    required this.onTest,
    required this.onOpenAiConfig,
  });

  final String title;
  final String engineId;
  final List<({String id, String label, bool needsKey})> engines;
  final TextEditingController keyController;
  final String? testResult;
  final ValueChanged<String?> onEngineChanged;
  final VoidCallback onSave;
  final VoidCallback onTest;
  final VoidCallback onOpenAiConfig;

  bool get _needsKey => engines.firstWhere((e) => e.id == engineId).needsKey;

  @override
  Widget build(BuildContext context) {
    final isSystemVideo = engineId == 'system-video';
    final isSystemImage = engineId == 'system-image';
    final isSystemEngine = isSystemVideo || isSystemImage;

    final summary = isSystemVideo
        ? VideoGenAdapterFactory.getSystemVideoConfigSummary()
        : (isSystemImage
            ? ImageGenAdapterFactory.getSystemImageConfigSummary()
            : (isConfigured: false, providerName: '', modelName: '', description: ''));

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.bgInput,
        borderRadius: AppTheme.borderRadiusSmall,
        border: Border.all(color: context.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                title,
                style: TextStyle(
                  color: context.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              if (isSystemEngine && summary.isConfigured)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: context.successText.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shield_outlined,
                          size: 11, color: context.successText),
                      const SizedBox(width: 4),
                      Text(
                        '密钥安全托管',
                        style:
                            TextStyle(fontSize: 10, color: context.successText),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: engineId,
            isDense: true,
            isExpanded: true,
            dropdownColor: context.bgCard,
            style: TextStyle(color: context.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              labelText: '引擎选择',
              labelStyle: TextStyle(color: context.textTertiary, fontSize: 12),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: [
              for (final e in engines)
                DropdownMenuItem(
                  value: e.id,
                  child: Text(
                    e.label,
                    style: const TextStyle(fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: onEngineChanged,
          ),
          if (isSystemEngine) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: context.bgCard,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: context.borderSubtle),
              ),
              child: Row(
                children: [
                  Icon(
                    summary.isConfigured
                        ? Icons.check_circle_outline
                        : Icons.warning_amber_rounded,
                    color: summary.isConfigured
                        ? context.successText
                        : context.warningText,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      summary.isConfigured
                          ? '当前模型: ${summary.description}（全局统一生效）'
                          : '系统全局尚未配置${isSystemVideo ? "视频" : "图像"}模型候选，请点击右侧按钮添加',
                      style: TextStyle(
                        fontSize: 12,
                        color: summary.isConfigured
                            ? context.textSecondary
                            : context.warningText,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.settings_suggest_outlined, size: 14),
                    label:
                        const Text('AI 基础设施配置', style: TextStyle(fontSize: 12)),
                    onPressed: onOpenAiConfig,
                  ),
                ],
              ),
            ),
          ] else if (_needsKey) ...[
            const SizedBox(height: 8),
            TextField(
              controller: keyController,
              obscureText: true,
              style: TextStyle(color: context.textPrimary, fontSize: 13),
              decoration: InputDecoration(
                labelText: '独立 API Key',
                hintText: '输入该引擎专用的 API Key',
                labelStyle:
                    TextStyle(color: context.textTertiary, fontSize: 12),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (_needsKey) ...[
                OutlinedButton(
                  onPressed: onSave,
                  child: const Text('保存 Key', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 8),
              ],
              OutlinedButton.icon(
                icon: const Icon(Icons.network_check, size: 14),
                label: const Text('测试可用性', style: TextStyle(fontSize: 12)),
                onPressed: onTest,
              ),
              const SizedBox(width: 12),
              if (testResult == 'testing')
                Row(
                  children: [
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                    Text('正在探测...',
                        style: TextStyle(
                            fontSize: 12, color: context.textTertiary)),
                  ],
                )
              else if (testResult == 'pass')
                Row(
                  children: [
                    Icon(Icons.check_circle,
                        size: 14, color: context.successText),
                    const SizedBox(width: 4),
                    Text('可用性校验通过',
                        style: TextStyle(
                            fontSize: 12,
                            color: context.successText,
                            fontWeight: FontWeight.w500)),
                  ],
                )
              else if (testResult == 'fail')
                Row(
                  children: [
                    Icon(Icons.cancel, size: 14, color: context.errorText),
                    const SizedBox(width: 4),
                    Text('不可用或未配置',
                        style: TextStyle(
                            fontSize: 12,
                            color: context.errorText,
                            fontWeight: FontWeight.w500)),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}
