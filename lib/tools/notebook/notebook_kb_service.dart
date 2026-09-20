import 'package:flutter/foundation.dart';

import '../../services/agent_loop.dart';
import '../../services/ai_logger.dart';
import '../../services/ai_service.dart';
import '../../services/web_search_service.dart';
import 'cjk_tokenizer.dart';
import 'markdown_converter.dart';
import 'note_store.dart';

/// 检索片段：一条命中笔记及其供 LLM 使用的上下文。
class KbFragment {
  final String noteId;
  final String title;

  /// 与查询最相关的正文片段（原文，非 bigram 化后的索引文本）。
  final String snippet;

  /// 资产字段（若该笔记是资产笔记）。
  final String? assetCategory;
  final DateTime? assetExpiryDate;

  /// 凭证附件文件名（供回答指引用户定位凭证）。
  final List<String> credentialFiles;

  const KbFragment({
    required this.noteId,
    required this.title,
    required this.snippet,
    this.assetCategory,
    this.assetExpiryDate,
    this.credentialFiles = const [],
  });

  bool get isAsset => assetCategory != null || assetExpiryDate != null;
}

/// 问答回答。`noMatch` 为 true 时表示无相关笔记——此时**不伪造答案**。
class KbAnswer {
  final String text;
  final List<KbCitation> citations;
  final bool noMatch;
  final String? error;

  const KbAnswer({
    required this.text,
    this.citations = const [],
    this.noMatch = false,
    this.error,
  });

  const KbAnswer.noMatch(String message)
      : text = message,
        citations = const [],
        noMatch = true,
        error = null;

  const KbAnswer.failure(String message)
      : text = message,
        citations = const [],
        noMatch = false,
        error = message;
}

/// 回答中的引用，供 UI 渲染可点击链接定位到笔记。
class KbCitation {
  final String noteId;
  final String title;
  const KbCitation({required this.noteId, required this.title});
}

/// 笔记本知识库服务（阶段二）。
///
/// 薄编排层：检索走 [NoteStore.searchNotes]（CJK bigram FTS），生成走
/// [AiService.chat]，不持有自己的存储。
class NotebookKbService {
  NotebookKbService._();
  static final NotebookKbService instance = NotebookKbService._();

  /// 每条片段喂给 LLM 的最大字符数。个人笔记规模下 800 字足以覆盖上下文。
  static const int _snippetBudget = 800;

  /// 检索相关笔记。
  ///
  /// 步骤：FTS5 取 top-N（已按 bm25 相关性排序）→ 每条笔记取原文 →
  /// 截取与查询最相关的片段 → 附资产/凭证信息。
  Future<List<KbFragment>> retrieve(String query, {int limit = 5}) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];
    // 无有效 token（纯标点/空白）时直接返回，不触碰数据库。
    if (cjkFtsQuery(trimmed).isEmpty) return const [];

    final notes = await NoteStore.instance.db.searchNotes(trimmed);
    if (notes.isEmpty) return const [];

    final fragments = <KbFragment>[];
    for (final note in notes.take(limit)) {
      final markdown = MarkdownConverter.deltaToMarkdown(note.deltaJson);
      final snippet = _relevantSnippet(markdown, trimmed);

      var credentialFiles = const <String>[];
      try {
        final creds = await NoteStore.instance.db.credentialsForNote(note.id);
        credentialFiles = creds
            .map((a) => a.filename ?? a.localPath.split('/').last)
            .toList();
      } catch (_) {}

      fragments.add(KbFragment(
        noteId: note.id,
        title: note.title,
        snippet: snippet,
        assetCategory: note.assetCategory,
        assetExpiryDate: note.assetExpiryDate,
        credentialFiles: credentialFiles,
      ));
    }
    return fragments;
  }

  /// 显式联网问答：跳过笔记检索，直接用 [WebSearchService] 取资料再让 LLM 作答。
  ///
  /// 供问答面板在「笔记本无相关记录」时由用户主动触发的降级路径。
  Future<KbAnswer> askWeb(String question, {int limit = 5}) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      return const KbAnswer.noMatch('请输入问题。');
    }

    try {
      final res = await WebSearchService.instance.search(trimmed, limit: limit);
      if (res.isError) {
        return KbAnswer.failure('联网检索失败：${res.error ?? '未知原因'}');
      }
      final context = res.results
          .map((r) => '- ${r.title}\n  ${r.url}\n  ${r.snippet}')
          .join('\n\n');
      if (context.isEmpty) {
        return const KbAnswer.noMatch('联网也没有检索到相关结果。');
      }

      final answer = await AiService.instance.chat(
        slot: 'text',
        messages: [
          {
            'role': 'system',
            'content': '你是一个信息助手。请依据下面的联网检索结果回答用户问题，'
                '注明来源链接，不要编造结果里没有的信息。',
          },
          {'role': 'user', 'content': '联网检索结果：\n\n$context\n\n我的问题：$trimmed'},
        ],
        timeout: const Duration(seconds: 90),
      );
      final text = answer.text.trim();
      return KbAnswer(
        text: text.isEmpty ? '（模型返回了空回答）' : text,
      );
    } catch (e) {
      AiLogger.logError('笔记本联网问答失败: $e');
      return KbAnswer.failure('联网问答出错：$e');
    }
  }

  /// 问答。检索命中则交给 LLM 基于片段作答并附引用；无命中则明确告知
  /// 无相关笔记，**不伪造答案**。
  ///
  /// 走共享 [AgentLoop]，注入三个工具：`notebook_search`（本服务 retrieve）、
  /// `web_search` / `scrape`（[WebSearchService]）。这样用户问笔记里没有的内容
  /// 时，模型可自行降级到联网检索。
  Future<KbAnswer> ask(String question, {int limit = 5}) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      return const KbAnswer.noMatch('请输入问题。');
    }

    final fragments = await retrieve(trimmed, limit: limit);
    if (fragments.isEmpty) {
      return const KbAnswer.noMatch(
        '你的笔记本里没有与这个问题相关的记录。可以换个说法，或到「AI 咨询与检索」里联网查询。',
      );
    }

    final context = _buildContext(fragments);
    final initialPrompt = '以下是我笔记本里检索到的相关记录：\n\n$context\n\n'
        '我的问题：$trimmed';

    try {
      final result = await AgentLoop.run(
        systemPrompt: _systemPromptWithTools,
        initialPrompt: initialPrompt,
        execute: _executeTool,
        maxIterations: 3,
        timeout: const Duration(seconds: 90),
      );

      final text = result.text.trim();
      return KbAnswer(
        text: text.isEmpty ? '（模型返回了空回答）' : text,
        citations: fragments
            .map((f) => KbCitation(noteId: f.noteId, title: f.title))
            .toList(),
      );
    } catch (e) {
      AiLogger.logError('笔记本问答失败: $e');
      return KbAnswer.failure('生成回答时出错：$e');
    }
  }

  /// 笔记本问答可用工具。笔记检索优先，联网作为兜底。
  static const List<AgentTool> kbTools = [
    AgentTool(
      name: 'notebook_search',
      description: '在我的笔记本中检索相关记录。当已有上下文不足时可用更宽的关键词再查一次。',
      inputSchema: {'query': 'string'},
    ),
    AgentTool(
      name: 'web_search',
      description: '联网搜索。仅当笔记本记录里确实没有答案、且问题需要最新或外部信息时使用。',
      inputSchema: {'query': 'string', 'limit': 'int'},
    ),
    AgentTool(
      name: 'scrape',
      description: '抓取指定网址的正文。已知确切 URL 且需要其内容时使用。',
      inputSchema: {'url': 'string'},
    ),
  ];

  /// 工具执行：笔记本检索走本服务，联网走 [WebSearchService]。
  Future<AgentToolOutcome> _executeTool(
    String name,
    Map<String, dynamic> args,
  ) async {
    try {
      switch (name) {
        case 'notebook_search':
          final q = (args['query'] as String?)?.trim() ?? '';
          if (q.isEmpty) return const AgentToolOutcome.failure('缺少 query 参数');
          final found = await retrieve(q);
          if (found.isEmpty) {
            return const AgentToolOutcome.success('（笔记本中未检索到相关记录）');
          }
          return AgentToolOutcome.success(_buildContext(found));

        case 'web_search':
          final q = (args['query'] as String?)?.trim() ?? '';
          if (q.isEmpty) return const AgentToolOutcome.failure('缺少 query 参数');
          final limit = (args['limit'] as num?)?.toInt() ?? 5;
          final res = await WebSearchService.instance.search(q, limit: limit);
          if (res.isError) {
            return AgentToolOutcome.failure(res.error ?? '联网检索失败');
          }
          final text = res.results
              .map((r) => '- ${r.title}\n  ${r.url}\n  ${r.snippet}')
              .join('\n\n');
          return AgentToolOutcome.success(text.isEmpty ? '（无结果）' : text);

        case 'scrape':
          final url = (args['url'] as String?)?.trim() ?? '';
          if (url.isEmpty) return const AgentToolOutcome.failure('缺少 url 参数');
          final res = await WebSearchService.instance.scrape(url);
          if (res.isError) {
            return AgentToolOutcome.failure(res.error ?? '抓取失败');
          }
          return AgentToolOutcome.success(
              res.content.isEmpty ? '（页面为空）' : res.content);

        default:
          return AgentToolOutcome.failure('未知工具: $name');
      }
    } catch (e) {
      return AgentToolOutcome.failure(e.toString());
    }
  }

  static String get _systemPromptWithTools => '''
你是一个个人知识库助手。用户会问关于他自己笔记内容的问题。

**优先依据笔记回答**。只有在笔记记录确实无法回答、且问题需要最新或外部信息时，
才可以调用联网工具。调用工具时严格输出且仅输出如下 JSON 代码块：

```tool_call
{
  "name": "工具名称",
  "arguments": { "参数名": "参数值" }
}
```

可用工具：

${AgentLoop.renderTools(kbTools)}

规则：
1. 笔记记录优先，联网是兜底，不要为了联网而联网。
2. 如果记录里有资产/凭证信息（如延保服务、保单、到期日），务必明确指出，
   并引导用户查看对应凭证附件。
3. 回答简洁，用中文，必要时引用笔记标题。
4. 如果笔记与联网都不足以回答，直接说明，不要猜测。
''';

  static const String _systemPrompt = '''
你是一个个人知识库助手。用户会问关于他自己笔记内容的问题。

规则：
1. 只依据下面提供的【笔记记录】回答，不要编造记录里没有的信息。
2. 如果记录里有资产/凭证信息（如延保服务、保单、到期日），务必明确指出，
   并引导用户查看对应凭证附件。
3. 回答简洁，用中文，必要时引用笔记标题。
4. 如果记录不足以回答，直接说明记录里没有相关信息，不要猜测。
''';

  /// 无联网工具的纯笔记问答 prompt（保留给不需要联网的场景/测试参考）。
  @visibleForTesting
  static String get debugPlainSystemPrompt => _systemPrompt;

  String _buildContext(List<KbFragment> fragments) {
    final buffer = StringBuffer();
    for (var i = 0; i < fragments.length; i++) {
      final f = fragments[i];
      buffer.writeln('【笔记 ${i + 1}】${f.title}');
      if (f.assetCategory != null) {
        buffer.writeln('  资产类别：${f.assetCategory}');
      }
      if (f.assetExpiryDate != null) {
        buffer.writeln('  到期日：${_fmtDate(f.assetExpiryDate!)}');
      }
      if (f.credentialFiles.isNotEmpty) {
        buffer.writeln('  凭证附件：${f.credentialFiles.join('、')}');
      }
      buffer.writeln('  内容：${f.snippet}');
      buffer.writeln();
    }
    return buffer.toString();
  }

  /// 截取与查询最相关的片段：以首个命中的 bigram 为中心开窗；
  /// 未找到命中位置（如仅标题命中）时取正文开头。
  String _relevantSnippet(String markdown, String query) {
    final text = markdown.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.length <= _snippetBudget) return text;

    final tokens = cjkBigrams(query);
    var hitIndex = -1;
    for (final t in tokens) {
      final idx = text.indexOf(t);
      if (idx >= 0) {
        hitIndex = idx;
        break;
      }
    }
    if (hitIndex < 0) return text.substring(0, _snippetBudget);

    // 命中点居中开窗，并向两侧取整到词边界不易，直接截断即可。
    final half = _snippetBudget ~/ 2;
    var start = hitIndex - half;
    if (start < 0) start = 0;
    var end = start + _snippetBudget;
    if (end > text.length) {
      end = text.length;
      start = end - _snippetBudget;
      if (start < 0) start = 0;
    }
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix${text.substring(start, end)}$suffix';
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @visibleForTesting
  String debugBuildContext(List<KbFragment> fragments) => _buildContext(fragments);
}
