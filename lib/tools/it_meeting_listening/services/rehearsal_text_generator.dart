/// 基于应用「AI 能力配置」text 槽位的文本生成实现。
///
/// 走 [AiService.chat] 而不是自己拼 HTTP：槽位路由、多候选降级、供应商健康
/// 冷却都是既有能力，重造一遍等于放弃自动愈合。实测上一轮 Edge-TTS 就是
/// 因为绕开这套自己拼端点而失效的。
library;

import '../../../services/ai_service.dart';
import 'rehearsal_llm.dart';

/// 经 text 槽位生成文本。
class SlotTextGenerator implements RehearsalTextGenerator {
  /// 槽位名。讲稿与剧本都用 text 槽位。
  final String slot;

  /// 超时。整场剧本一次生成，输出可能几千词，用 90 秒的对话默认值。
  final Duration timeout;

  const SlotTextGenerator({
    this.slot = 'text',
    this.timeout = AiService.defaultChatTimeout,
  });

  @override
  Future<String> generate(String prompt) async {
    final result = await AiService.instance.chat(
      slot: slot,
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      timeout: timeout,
    );
    final text = result.text.trim();
    if (text.isEmpty) {
      throw StateError('模型返回了空内容');
    }
    return text;
  }
}
