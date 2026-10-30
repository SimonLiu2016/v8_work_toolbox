/// 排练会议的 LLM 调用抽象。
///
/// 讲稿生成与剧本生成是两个独立的 text 槽位调用（design D1）。这里把"怎么调"
/// 封成接口，使两件事可被分别注入假实现测试，而不必 mock 整个 [AiService]。
library;

import '../models/rehearsal_models.dart';

/// 文本生成能力。
abstract class RehearsalTextGenerator {
  /// 用 [prompt] 调一次 text 槽位，返回模型输出。
  ///
  /// 失败时抛出异常——由调用方决定是提示用户还是重试。
  Future<String> generate(String prompt);
}

/// 讲稿生成器（阶段一）。
abstract class SpeechDraftGenerator {
  /// 基于材料生成 Simon 第一人称英文讲稿。
  Future<SpeechDraft> generateDraft(RehearsalMaterial material);
}

/// 会议剧本生成器（阶段二）。
abstract class MeetingScriptGenerator {
  /// 基于材料与讲稿生成 5 角色会议剧本。
  Future<MeetingScript> generateScript({
    required RehearsalMaterial material,
    required SpeechDraft draft,
    required int targetMinutes,
  });
}
