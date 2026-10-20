import 'package:flutter/foundation.dart';
import '../../../../services/ai_service.dart';
import 'novel_repository.dart';

/// AI 改写风格类型
enum RewriteStyle {
  polish,       // 润色文笔
  expand,       // 扩写细节与感官描写
  condense,     // 提炼精简
  firstPerson,  // 第一人称视角改写
  thirdPerson,  // 第三人称视角改写
  dramatic,     // 增强戏剧冲突与悬念
}

/// 章节 AI 编辑、改写与续写服务
class NovelAiEditorService {
  NovelAiEditorService._();
  static final NovelAiEditorService instance = NovelAiEditorService._();

  final NovelRepository _repo = NovelRepository.instance;

  /// 单章 AI 改写
  Future<String> rewriteChapter({
    required String originalContent,
    required RewriteStyle style,
    String? customInstructions,
  }) async {
    String instruction = '';
    switch (style) {
      case RewriteStyle.polish:
        instruction = '对文本进行文学润色，优化措辞，修复语病，保持原意与剧情走向不变。';
        break;
      case RewriteStyle.expand:
        instruction = '对文本进行细节扩写，增强角色神态、环境氛围与心理描写，使场景更加生动立体。';
        break;
      case RewriteStyle.condense:
        instruction = '提炼精简文本，去除冗余描述与废话，保留核心剧情动作与关键对话。';
        break;
      case RewriteStyle.firstPerson:
        instruction = '将文本视角转换为第一人称（“我”的视角），展现深刻的内心独白与第一视角观察。';
        break;
      case RewriteStyle.thirdPerson:
        instruction = '将文本视角转换为第三人称客观视角叙事。';
        break;
      case RewriteStyle.dramatic:
        instruction = '增强场景的紧张感、对立冲突与章节末尾的悬念反转，使节奏更加紧凑抓人。';
        break;
    }

    if (customInstructions != null && customInstructions.trim().isNotEmpty) {
      instruction += '\n补充用户特定要求：$customInstructions';
    }

    final prompt = '''
你是一名资深网络小说金牌主编兼创作导师。请对以下小说正文片段进行改写。
【改写要求】
$instruction

【输出规则】
直接输出改写后的完整小说正文，段落前空四个半角空格或两个全角空格。严禁输出任何“好的”、“这是改写后的内容”等废话说明。

【待改写原文】：
$originalContent
''';

    try {
      final res = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );
      return res.text.trim();
    } catch (e) {
      debugPrint('[NovelAiEditorService] rewriteChapter error: $e');
      rethrow;
    }
  }

  /// 依据前文剧情与设定大纲，AI 创作续写新章节
  Future<Map<String, String>> generateNextChapter({
    required String novelId,
    required int nextChapterIndex,
    String? userPrompt,
  }) async {
    final novel = await _repo.getNovel(novelId);
    final novelTitle = novel?.title ?? '未知小说';
    final description = novel?.description ?? '';

    // 获取前 1~2 章作为剧情参考上下文
    String contextText = '';
    final existingChapters = await _repo.getChapterIndices(novelId);
    if (existingChapters.isNotEmpty) {
      final prevIndex = nextChapterIndex > 1 ? nextChapterIndex - 1 : existingChapters.last.chapterIndex;
      final prevChapter = await _repo.getChapter(novelId, prevIndex);
      if (prevChapter != null) {
        final content = prevChapter.content;
        contextText = '【前一章（${prevChapter.title}）结尾剧情片段】：\n${content.length > 1500 ? content.substring(content.length - 1500) : content}';
      }
    }

    final prompt = '''
你是一名畅销小说作家。正在创作小说《$novelTitle》。
【故事背景设定】：
$description

$contextText

【创作目标】：
请续写第 $nextChapterIndex 章。
${userPrompt != null && userPrompt.trim().isNotEmpty ? '【本章剧情走向要求】：$userPrompt' : '请根据前文剧情自然推演，设计一个包含情节推进或戏剧冲突的高潮章节。'}

【输出格式要求】：
请严格按以下格式输出（第一行为标题，后面为正文）：
第 $nextChapterIndex 章 章节标题
    正文第一段...
    正文第二段...
''';

    try {
      final res = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {'role': 'user', 'content': prompt},
        ],
      );

      final fullOutput = res.text.trim();
      final lines = fullOutput.split('\n');
      String title = '第 $nextChapterIndex 章';
      String body = fullOutput;

      if (lines.isNotEmpty && lines.first.trim().startsWith('第')) {
        title = lines.first.trim();
        body = lines.sublist(1).join('\n').trim();
      }

      return {
        'title': title,
        'content': body,
      };
    } catch (e) {
      debugPrint('[NovelAiEditorService] generateNextChapter error: $e');
      rethrow;
    }
  }
}
