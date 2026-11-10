/// 当前 TTS 槽位绑定的供应商探测，及由此派生的音色候选/默认值/风格指令。
///
/// **为什么单独一层**：生词本（`vocabulary_study_store` / `vocabulary_browser_dialog`）、
/// 真实会议的「说话人与音色」UI、说话人散列兜底与两个烘焙器都要回答「当前 TTS
/// 槽位是否绑定 MiMo、该用哪套音色候选」。若各写一遍探测逻辑，将来「MiMo 判定
/// 规则变了」就要改多处，且极易出现「一处认 MiMo、一处不认」的分叉——这正是
/// 本仓库 v0.2.0 之后真实会议链路遗漏 MiMo 适配的根因。
///
/// 所有探测都是**同步**读 `AiConfigStore.instance` 的纯查询，投影自
/// `OpenAiTtsEngine.isMimoModel` 的唯一判定点。
library;

import '../../../services/ai_config_store.dart';
import '../../reader/models/reader_models.dart';
import '../../reader/services/tts_engine.dart';
import 'role_voice_map.dart';

/// TTS 槽位绑定探测结果（音色候选 / 默认音色 / 默认风格指令）。
///
/// 非 MiMo 时一律退回既有 `VoicePool`（StepFun 角色音色池）行为，保证
/// 改动前的语义完全不变。
class TtsBindingProbe {
  TtsBindingProbe._();

  /// 当前 TTS 槽位是否绑定到小米 MiMo。
  ///
  /// 投影自 [OpenAiTtsEngine.isMimoModel]，遍历 `slotBindings['tts']` 的候选，
  /// 取**首个启用**的供应商判定。无任何绑定或全部禁用时返回 false。
  static bool isMimo() {
    final store = AiConfigStore.instance;
    final candidates = store.slotBindings['tts'] ?? const <SlotCandidate>[];
    for (final cand in candidates) {
      final provider = store.providers.cast<AiProviderConfig?>().firstWhere(
        (p) => p?.id == cand.providerId && p?.enabled == true,
        orElse: () => null,
      );
      if (provider == null) continue;
      return OpenAiTtsEngine.isMimoModel(
        cand.model,
        baseUrl: provider.baseUrl,
        providerName: provider.name,
      );
    }
    return false;
  }

  /// 当前音色候选列表。
  ///
  /// MiMo → [TtsVoiceOption.defaultMimoVoices]（官方预置音色）；
  /// 非 MiMo → [VoicePool.all] 映射为 [TtsVoiceOption]（行为与现状等价）。
  static List<TtsVoiceOption> voiceOptions() {
    if (isMimo()) return TtsVoiceOption.defaultMimoVoices;
    return VoicePool.all
        .map(
          (v) => TtsVoiceOption(
            id: v.id,
            name: v.label,
            language: '',
            gender: v.gender == VoiceGender.female ? 'female' : 'male',
            mode: TtsMode.customAi,
            description: 'F0 ${v.measuredF0}Hz',
          ),
        )
        .toList();
  }

  /// 当前供应商合法音色标识集合。
  static Set<String> validVoiceIds() =>
      voiceOptions().map((v) => v.id).toSet();

  /// 判断指定音色是否为当前 TTS 供应商明确不兼容的异构音色。
  ///
  /// - MiMo 环境下：StepFun 角色音色（[VoicePool.all]）均不兼容；
  /// - 非 MiMo 环境下：MiMo 专有音色（[TtsVoiceOption.mimoSupportedVoiceIds]）均不兼容；
  /// - 其他未知的自定义或测试音色不主动判定为不兼容，避免误伤。
  static bool isIncompatibleVoice(String voiceId) {
    final v = voiceId.trim();
    if (v.isEmpty) return false;
    if (isMimo()) {
      return VoicePool.all.any((p) => p.id == v);
    } else {
      return TtsVoiceOption.mimoSupportedVoiceIds.contains(v);
    }
  }

  /// 当前默认音色标识。
  ///
  /// MiMo → `mimo_default`；非 MiMo → [VoicePool.zhixingjiejie]（与
  /// [VoicePool.zhixingjiejie.id] 一致，保持改动前默认）。
  static String defaultVoiceId() {
    if (isMimo()) return 'mimo_default';
    return VoicePool.zhixingjiejie.id;
  }

  /// 当前默认 MiMo 风格指令。
  ///
  /// MiMo → 保守默认（自然语言语速/情感）；非 MiMo → 空串（MiMo 之外的
  /// 引擎忽略该字段）。
  static String defaultStyle() {
    if (!isMimo()) return '';
    return '自然、清晰、语速适中、略带情感';
  }
}
