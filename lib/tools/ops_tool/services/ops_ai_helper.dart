import '../../../services/ai_service.dart';

class OpsAiHelper {
  OpsAiHelper._();

  static Future<String> analyzeAnomaly({
    required String sectionTitle,
    required String sectionContent,
  }) async {
    const systemPrompt =
        '你是一位资深 DevOps 与运营自动化专家。请根据提供的报告或指标内容，进行深度异常研判，输出清晰严谨的：1. 异常现状识别；2. 潜在根因推断；3. 优先级排序与处置建议。使用精简结构化的 Markdown 格式呈现。';

    final prompt = '''
请对以下【$sectionTitle】分节的内容进行智能异常研判与归因分析：

```
$sectionContent
```
''';

    final result = await AiService.instance.chat(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': prompt},
      ],
    );
    return result.text;
  }

  static Future<String> generateSummary({
    required String reportTitle,
    required String reportMarkdown,
  }) async {
    const systemPrompt =
        '你是一位资深运维运营分析师，擅长提炼关键业务与系统运行态势摘要。输出需包含：总体运行结论、关键告警与波动、待办跟进项。使用干净的 Markdown 排版。';

    final prompt = '''
请为以下报告《$reportTitle》提炼一份综合运营摘要：

$reportMarkdown
''';

    final result = await AiService.instance.chat(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': prompt},
      ],
    );
    return result.text;
  }

  static Future<String> chatWithOps({
    required String question,
    String? context,
  }) async {
    const systemPrompt =
        '你是磐石运维智能助手，为开发者和运维工程师提供 GitLab/Jenkins/ArgoCD 流水线排障、脚本编写、指标分析与操作指导。';

    final prompt = context != null && context.isNotEmpty
        ? '参考上下文：\n$context\n\n用户问题：\n$question'
        : question;

    final result = await AiService.instance.chat(
      messages: [
        {'role': 'system', 'content': systemPrompt},
        {'role': 'user', 'content': prompt},
      ],
    );
    return result.text;
  }
}
