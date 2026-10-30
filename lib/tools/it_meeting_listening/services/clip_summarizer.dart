/// 片段摘要生成。
///
/// 摘要是"这段会议达成了什么结论"的一句话说明，烘焙阶段生成一次并落盘，
/// 离线播放时按需展开即可（design D11）。
///
/// **只给长片段生成**：短片段（< 60s）一句话就说完了，摘要既没信息量，
/// 又是一次 LLM 调用。实测 incident 片段的结论在第 5-6 轮而不是首句——所以
/// 纯启发式抽首句抓不到结论，必须让模型读全文。
library;

import 'package:flutter/foundation.dart';

import '../../../services/ai_service.dart';
import '../models/listening_models.dart';

/// 摘要生成器。
class ClipSummarizer {
  /// 只为不短于该时长的片段生成摘要（毫秒）。
  static const int minSummaryMs = 60000;

  /// 单次调用的超时。
  static const Duration timeout = Duration(seconds: 60);

  /// 提示词：要求"议题 + 结论"两段式。
  ///
  /// 固定这两项是刻意的：IT 会议里"讨论了什么"和"最终决定了什么"是两回事，
  /// 只给议题的摘要对"抓结论"这个学习目标没有帮助。
  static const String systemPrompt = '''
你是一名技术会议记录助理。下面给你一段 IT 研发会议的英文对话转写。

请用**中文**写一句话摘要，必须包含两个部分，用「｜」分隔：
1. 议题：这段对话在讨论什么
2. 结论：这段对话最终确定或决定了什么

要求：
- 全文不超过 60 字
- 保留关键的技术名词与数字（如 rollback、503、1,200 transactions）
- 如果对话里没有明确结论，结论部分写「未形成明确结论」
- **只输出摘要本身**，不要任何解释、前言或引号

示例输出：
支付服务因配置变更返回 503｜决定回滚该配置变更，并让上游供应商核查状态页''';

  /// 为一个片段生成摘要。
  ///
  /// 返回 null 表示不生成（片段太短）或生成失败——**失败不阻塞烘焙**：
  /// 摘要是锦上添花，音频才是主体。
  Future<String?> summarize(Clip clip) async {
    if (clip.durationMs < minSummaryMs) return null;
    if (clip.turns.isEmpty) return null;

    final transcript = clip.turns
        .map((t) => '${t.displayName}: ${t.rawText}')
        .join('\n');

    try {
      final result = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': transcript},
        ],
        timeout: timeout,
      );
      return _clean(result.text);
    } catch (e) {
      debugPrint('[ClipSummarizer] 摘要生成失败（${clip.id}）: $e');
      return null;
    }
  }

  /// 清洗模型输出。
  ///
  /// 模型有时会带上"摘要："前缀、引号或多余换行——那些不该出现在摘要里。
  static String _clean(String raw) {
    var text = raw.trim();
    // 去掉常见的包装
    for (final prefix in ['摘要：', '摘要:', 'Summary:', 'summary:']) {
      if (text.startsWith(prefix)) text = text.substring(prefix.length).trim();
    }
    text = text.replaceAll(RegExp(r'^["“]|["”]$'), '').trim();
    // 折叠换行成空格（摘要应该是一句话）
    text = text.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
    return text;
  }

  /// 解析「议题｜结论」格式，供 UI 分开展示。
  ///
  /// 解析不出分隔符时，整段作为议题，结论留空——UI 侧不因为格式问题报错。
  static ({String topic, String conclusion}) split(String summary) {
    if (summary.isEmpty) return (topic: '', conclusion: '');
    final parts = summary.split('｜');
    if (parts.length < 2) return (topic: summary, conclusion: '');
    return (
      topic: parts.first.trim(),
      conclusion: parts.sublist(1).join('｜').trim(),
    );
  }
}
