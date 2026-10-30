/// 汇报人文稿生成（阶段一）。
///
/// **为什么单独一次调用**：讲稿是 Simon 的单人口述，要结构化、分议题、保留
/// 材料细节；剧本是五人对话，要在讲稿基础上演化出追问与质疑。一次生成会让
/// 模型同时做两件关注点不同的事，两边都做不好，且讲稿改了剧本要跟着全废
/// （design D1）。
///
/// **为什么要求占位标记**：会前用户自己会补数据。让模型在信息不足处写
/// `[待补充: ...]`，用户一眼能看到哪里要补；编造数字则是**教错**——用户照着
/// 念出去就是事故。
library;

import '../models/rehearsal_models.dart';
import 'material_importer.dart';
import 'rehearsal_llm.dart';

/// 讲稿生成失败。
class DraftGenerationException implements Exception {
  DraftGenerationException(this.message);
  final String message;
  @override
  String toString() => 'DraftGenerationException: $message';
}

/// 讲稿生成器。
class SpeechDraftGeneratorImpl implements SpeechDraftGenerator {
  /// 目标时长对应的节数下限。
  ///
  /// 一节约 1.5-3 分钟口述。节太少说明模型把多个议题揉进了一节，用户就没法
  /// 按议题单独预听与修改。
  static const int minSections = 3;

  final RehearsalTextGenerator _generator;

  /// [maxMaterialChars] 送 LLM 的材料截断长度。
  final int maxMaterialChars;

  const SpeechDraftGeneratorImpl(
    this._generator, {
    this.maxMaterialChars = 24000,
  });

  @override
  Future<SpeechDraft> generateDraft(RehearsalMaterial material) async {
    if (material.text.trim().isEmpty) {
      throw DraftGenerationException('材料内容为空，无法生成讲稿');
    }

    final prompt = _buildPrompt(material);
    final String output;
    try {
      output = await _generator.generate(prompt);
    } catch (e) {
      throw DraftGenerationException('讲稿生成失败：$e');
    }

    final sections = parseSections(output);
    if (sections.isEmpty) {
      throw DraftGenerationException('讲稿解析失败：模型输出里没有可分节的内容');
    }
    if (sections.length < minSections) {
      throw DraftGenerationException(
          '讲稿只有 ${sections.length} 节，少于 $minSections 节——'
          '模型可能没按议题分节，请重试');
    }

    return SpeechDraft(
      id: 'draft_${material.id}',
      materialId: material.id,
      title: '${material.title} · 汇报讲稿',
      sections: sections,
      generatedAt: DateTime.now(),
    );
  }

  /// 构造 prompt。
  ///
  /// 只约束**形式与纪律**（第一人称、英文、分节、口语、不编造），不指定内容——
  /// 内容全从材料来。
  String _buildPrompt(RehearsalMaterial material) {
    final body = MaterialImporter.truncateForPrompt(material.text,
        maxChars: maxMaterialChars);
    return '''
You are writing the English speech draft that Simon (a comall engineer) will
deliver in an upcoming meeting. Write it from Simon's first-person point of view.

SOURCE MATERIAL (the only source of facts — do not invent anything):
"""
$body
"""

REQUIREMENTS:
1. Write in English, as a spoken meeting remark. Short sentences, contractions,
   natural pauses. NOT a written report.
2. Organise into sections by agenda topic. Each section starts with a line
   "## <topic>" followed by the spoken paragraphs.
3. Keep every technical term, metric, version number, customer name and
   conclusion from the material VERBATIM. Never summarise a number away.
4. If the material lacks data for a point, write "[待补充: what is missing]"
   at that spot. NEVER fabricate a number.
5. At least $minSections sections.

Output only the draft, starting with the first "## " line.''';
  }

  /// 解析模型输出为分节结构。
  ///
  /// 分节标记是 `## 标题`。首节若缺标题（模型忘了写第一个 `##`）补一个通用标题，
  /// 不因此丢掉内容。
  static List<DraftSection> parseSections(String output) {
    final lines = output.split('\n');
    final sections = <DraftSection>[];
    var title = '';
    var buffer = <String>[];

    void flush() {
      final body = buffer.join('\n').trim();
      if (title.isNotEmpty || body.isNotEmpty) {
        sections.add(DraftSection(title: title, body: body));
      }
      buffer = <String>[];
    }

    for (final line in lines) {
      final m = RegExp(r'^\s*#{1,3}\s+(.+)$').firstMatch(line);
      if (m != null) {
        flush();
        title = m.group(1)!.trim();
        continue;
      }
      buffer.add(line);
    }
    flush();

    // 去掉完全空的节（标题与正文都空）。
    final nonEmpty =
        sections.where((s) => s.title.isNotEmpty || s.body.isNotEmpty).toList();
    if (nonEmpty.isEmpty) return const [];
    // 首节若无标题（模型忘了写第一个 ##），补一个通用标题。
    if (nonEmpty.first.title.isEmpty) {
      return [
        DraftSection(title: 'Opening', body: nonEmpty.first.body),
        ...nonEmpty.skip(1),
      ];
    }
    return nonEmpty;
  }
}
