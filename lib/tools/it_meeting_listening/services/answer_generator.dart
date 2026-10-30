/// 选段回答生成：针对会上被问到的问题，产出可以念出来的英文回答。
///
/// 两条路径，产物同形（一段英文 + 可选中文原文），所以插入端只需要一个入口：
///
/// ```
/// ① AI 直接给建议回答         → textEn = 模型输出, textZh = ''
/// ② 用户中文作答 → 译成英文    → textEn = 译文,     textZh = 用户原文
/// ```
///
/// **上下文用窗口而不是整篇**（design D7）：20 分钟的会整篇约 1.1 万字符，
/// 送得下；60 分钟的会到 4 万字符，其中大半与"这一问该怎么答"无关。窗口既
/// 省 token，又天然把"上下文"限定成真正相关的那一段。截断时明确告知。
///
/// **两条硬约束**：
/// - 不许编造数字、版本号、人名——照着念出去就是事故
/// - 信息不足时写 `[待补充: …]` 占位，让用户一眼看到哪里要补
library;

import '../models/real_meeting_models.dart';
import 'rehearsal_llm.dart';

/// 回答生成失败。
class AnswerGenerationException implements Exception {
  AnswerGenerationException(this.message);
  final String message;
  @override
  String toString() => 'AnswerGenerationException: $message';
}

/// 生成出来的回答草稿。
class AnswerDraft {
  /// 英文回答（送入合成与插入的就是它）。
  final String textEn;

  /// 中文原文（中文作答路径才有）。
  final String textZh;

  /// 上下文是否被截断（界面要提示用户）。
  final bool truncated;

  const AnswerDraft({
    required this.textEn,
    this.textZh = '',
    this.truncated = false,
  });
}

/// 回答生成器。
class AnswerGenerator {
  /// 上下文预算（字符）。英文约 0.3 token/字符，6000 字符约 1800 token，
  /// 加上提示词与输出仍远低于常见模型的上下文上限。
  final int maxContextChars;

  final RehearsalTextGenerator _generator;

  const AnswerGenerator(
    this._generator, {
    this.maxContextChars = 6000,
  });

  /// 让 AI 直接给一段英文回答。
  Future<AnswerDraft> suggestAnswer({
    required RealMeeting meeting,
    required int questionTurnIndex,
  }) async {
    final question = _turnAt(meeting, questionTurnIndex);
    final context = _buildContext(meeting, questionTurnIndex);
    final prompt = _suggestPrompt(meeting, question, context);

    final output = await _call(prompt);
    return AnswerDraft(textEn: output, truncated: context.truncated);
  }

  /// 把用户的中文回答译成英文，中文原文一并返回。
  Future<AnswerDraft> translateAnswer({
    required RealMeeting meeting,
    required int questionTurnIndex,
    required String chinese,
  }) async {
    final zh = chinese.trim();
    if (zh.isEmpty) {
      throw AnswerGenerationException('中文回答为空');
    }
    final question = _turnAt(meeting, questionTurnIndex);
    final context = _buildContext(meeting, questionTurnIndex);
    final prompt = _translatePrompt(meeting, question, context, zh);

    final output = await _call(prompt);
    return AnswerDraft(textEn: output, textZh: zh, truncated: context.truncated);
  }

  // ---------------------------------------------------------------------

  MeetingTurn? _turnAt(RealMeeting meeting, int index) {
    for (final t in meeting.turns) {
      if (t.index == index) return t;
    }
    return null;
  }

  /// 目标轮之前的一段窗口。
  ///
  /// 从紧邻的上一轮往回取，直到填满预算。**不取目标轮之后的轮次**：后续
  /// 发言往往已经把这个问题聊过去了，读进去会让回答偏离"我该怎么说"。
  ({String text, bool truncated}) _buildContext(
      RealMeeting meeting, int questionTurnIndex) {
    final before = meeting.turns
        .where((t) => t.index < questionTurnIndex)
        .toList();
    if (before.isEmpty) return (text: '', truncated: false);

    final picked = <MeetingTurn>[];
    var used = 0;
    for (var i = before.length - 1; i >= 0; i--) {
      final t = before[i];
      final cost = t.text.length + 8;
      if (used + cost > maxContextChars) break;
      picked.insert(0, t);
      used += cost;
    }
    return (
      text: picked.map((t) => '${t.slotId}: ${t.text}').join('\n'),
      truncated: picked.length < before.length,
    );
  }

  String _suggestPrompt(
      RealMeeting meeting, MeetingTurn? question, ({String text, bool truncated}) context) {
    final header = _header(meeting, context.truncated);
    final q = question == null
        ? '（未找到被提问的轮次）'
        : '${question.slotId}: ${question.text}';
    return '''
You are helping the user rehearse an English reply for a real meeting they attended.

$header
RECENT CONTEXT (verbatim transcript, most recent last):
"""
${context.text}
"""

THE QUESTION / REMARK THE USER WANTS TO ANSWER:
"""
$q
"""

TASK:
Write the user's spoken English reply to that question.

RULES:
1. English only, first person, spoken style. Short sentences, contractions,
   natural fillers are fine. This will be read aloud by a TTS engine.
2. Base every fact on the transcript above. NEVER invent numbers, versions,
   names, dates or commitments. If a fact is needed but absent, write
   "[待补充: what is missing]" at that spot.
3. Length: 2-6 sentences (roughly 20-80 words). It is a meeting turn, not a memo.
4. Do not restate the question. Answer it.
5. Output only the reply text — no headings, no quotes around it, no preamble.''';
  }

  String _translatePrompt(RealMeeting meeting, MeetingTurn? question,
      ({String text, bool truncated}) context, String chinese) {
    final header = _header(meeting, context.truncated);
    final q = question == null
        ? '（未找到被提问的轮次）'
        : '${question.slotId}: ${question.text}';
    return '''
You are translating the user's Chinese reply into the English they will speak in
a real meeting.

$header
RECENT CONTEXT (verbatim transcript, most recent last):
"""
${context.text}
"""

THE QUESTION BEING ANSWERED:
"""
$q
"""

THE USER'S REPLY IN CHINESE:
"""
$chinese
"""

TASK:
Produce the English spoken version of that reply.

RULES:
1. Keep the user's meaning, intent and hedging exactly. Do not add arguments
   they did not make.
2. English only, first person, spoken style, short sentences. It will be read
   aloud by a TTS engine, so avoid parentheses, slashes and bullet points.
3. Reuse the terminology from the transcript (same product names, same acronyms).
4. NEVER invent numbers, versions or names that are absent from the Chinese text
   or the transcript. If the Chinese leaves something vague, keep it vague.
5. Output only the English text — no Chinese, no headings, no preamble.''';
  }

  String _header(RealMeeting meeting, bool truncated) {
    final kw = meeting.keywords.isEmpty ? '' : meeting.keywords.join(', ');
    return '''
MEETING: ${meeting.title}
${kw.isEmpty ? '' : 'KEYWORDS: $kw'}
${truncated ? 'NOTE: the transcript was long, only the most recent turns before the question are included.' : ''}''';
  }

  Future<String> _call(String prompt) async {
    final String output;
    try {
      output = await _generator.generate(prompt);
    } catch (e) {
      throw AnswerGenerationException('生成失败：$e');
    }
    final cleaned = _clean(output);
    if (cleaned.isEmpty) {
      throw AnswerGenerationException('模型返回了空内容，请重试');
    }
    if (!RegExp(r'[A-Za-z]{2,}').hasMatch(cleaned)) {
      throw AnswerGenerationException('模型返回的内容不像英文回答，请重试');
    }
    return cleaned;
  }

  /// 剥掉常见的模型包装（代码围栏、首尾引号、空行）。
  static String _clean(String raw) {
    var text = raw.trim();
    // ```...``` 代码块
    final fence = RegExp(r'^```[a-zA-Z]*\n?([\s\S]*?)\n?```$').firstMatch(text);
    if (fence != null) text = fence.group(1)!.trim();
    // 首尾成对引号
    const pairs = {r'"': r'"', '“': '”'};
    pairs.forEach((open, close) {
      if (text.length > 1 && text.startsWith(open) && text.endsWith(close)) {
        text = text.substring(1, text.length - 1).trim();
      }
    });
    // 模型有时会在前面加 "Here is the reply:" 之类的一行
    final lines = text.split('\n');
    if (lines.length > 1 &&
        lines.first.length < 60 &&
        lines.first.trimRight().endsWith(':')) {
      text = lines.skip(1).join('\n').trim();
    }
    return text.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}
