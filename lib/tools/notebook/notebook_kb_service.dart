import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../services/agent_loop.dart';
import '../../services/ai_logger.dart';
import '../../services/ai_service.dart';
import '../../services/web_search_service.dart';
import 'appflowy_codec.dart';
import 'cjk_tokenizer.dart';
import 'note_database.dart';
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

  /// 命中的笔记是否沿星图扩展过（阶段四）。为 true 时 [graphHops] 说明跳数。
  final bool usedGraph;

  /// 星图扩展带入的额外笔记 id（不含 FTS 直接命中的）。
  final List<String> graphNoteIds;

  const KbAnswer({
    required this.text,
    this.citations = const [],
    this.noMatch = false,
    this.error,
    this.usedGraph = false,
    this.graphNoteIds = const [],
  });

  const KbAnswer.noMatch(String message)
      : text = message,
        citations = const [],
        noMatch = true,
        error = null,
        usedGraph = false,
        graphNoteIds = const [];

  const KbAnswer.failure(String message)
      : text = message,
        citations = const [],
        noMatch = false,
        error = message,
        usedGraph = false,
        graphNoteIds = const [];
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

  /// 取笔记正文纯文本。**不能**用 `MarkdownConverter.deltaToMarkdown`
  /// （Quill 专用解析器，对 AppFlowy 格式返回空串）。统一走
  /// [AppFlowyCodec.jsonToPlainText]。
  static String _notePlainText(String deltaJson) =>
      AppFlowyCodec.jsonToPlainText(deltaJson);

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
      final markdown = _notePlainText(note.deltaJson);
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

  /// 全部已有标签名（供建议去重）。
  Future<List<String>> _existingTagNames() async {
    try {
      final tags = await NoteStore.instance.allTags();
      return tags.map((t) => t.name).toList();
    } catch (_) {
      return const [];
    }
  }

  /// AI 建议标签。仅返回建议，**不写库**——由 UI 呈请用户确认后写入（design D7）。
  Future<List<String>> suggestTags(String noteId) async {
    final note = await NoteStore.instance.noteById(noteId);
    if (note == null) return const [];

    final body = _notePlainText(note.deltaJson);
    final existing = await _existingTagNames();
    final existingOwn = await _tagsOfNote(noteId);

    final res = await AiService.instance.chat(
      slot: 'text',
      messages: [
        {
          'role': 'system',
          'content': '你是笔记整理助手。根据笔记内容建议 1~5 个简短标签（每个 2~6 字）。\n'
              '只输出 JSON 数组，例如：["延保","家电","凭证"]。不要输出其他任何内容。\n'
              '不要重复已有标签。',
        },
        {
          'role': 'user',
          'content': '已有标签（勿重复）：${existing.join("、")}\n'
              '本笔记已有标签：${existingOwn.join("、")}\n\n'
              '笔记标题：${note.title}\n笔记内容：\n$body',
        },
      ],
      timeout: const Duration(seconds: 60),
    );

    return parseTagSuggestions(res.text, excluded: {...existing, ...existingOwn});
  }

  Future<List<String>> _tagsOfNote(String noteId) async {
    try {
      final tags = await NoteStore.instance.db.tagsForNote(noteId);
      return tags.map((t) => t.name).toList();
    } catch (_) {
      return const [];
    }
  }

  /// 解析模型返回的标签数组，去重并剔除 [excluded]。
  @visibleForTesting
  static List<String> parseTagSuggestions(
    String reply, {
    Set<String> excluded = const {},
  }) {
    final match = RegExp(r'\[[\s\S]*?\]').firstMatch(reply);
    if (match == null) return const [];
    try {
      final list = jsonDecode(match.group(0)!) as List;
      final out = <String>[];
      for (final item in list) {
        final name = item.toString().trim();
        if (name.isEmpty || excluded.contains(name) || out.contains(name)) continue;
        out.add(name);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  /// AI 建议关联。仅返回建议（含理由），**不写库**。
  ///
  /// 候选来自 FTS 检索同主题笔记；不把全部笔记标题塞进 prompt 以免超长。
  Future<List<LinkSuggestion>> suggestLinks(String noteId) async {
    final note = await NoteStore.instance.noteById(noteId);
    if (note == null) return const [];

    final body = _notePlainText(note.deltaJson);
    // 用标题 + 正文开头做检索词，找同主题候选
    final candidates = await retrieve('${note.title} ${body.length > 120 ? body.substring(0, 120) : body}',
        limit: 8);
    final pool = candidates.where((c) => c.noteId != noteId).toList();
    if (pool.isEmpty) return const [];

    final already = await NoteStore.instance.relatedNotes(noteId);
    final alreadyIds = already.map((r) => r.noteId).toSet();

    final list = pool
        .map((c) => '- id=${c.noteId}｜标题：${c.title}｜摘要：${c.snippet}')
        .join('\n');

    final res = await AiService.instance.chat(
      slot: 'text',
      messages: [
        {
          'role': 'system',
          'content': '你是笔记整理助手。判断候选笔记与当前笔记是否真正相关（同一事物、'
              '同一订单、同一主题的延续等）。\n'
              '只输出 JSON 数组，每项形如 {"noteId":"...","reason":"简述关联理由（10字内）"}。\n'
              '只列出确实相关的，最多 5 条。不相关就输出 []。不要输出其他任何内容。',
        },
        {
          'role': 'user',
          'content': '当前笔记标题：${note.title}\n当前笔记内容：\n$body\n\n'
              '候选笔记：\n$list',
        },
      ],
      timeout: const Duration(seconds: 60),
    );

    return parseLinkSuggestions(
      res.text,
      validIds: pool.map((c) => c.noteId).toSet(),
      excludedIds: alreadyIds,
      titleOf: {for (final c in pool) c.noteId: c.title},
    );
  }

  /// 解析模型返回的关联建议，剔除无效 id 与已有/重复关联。
  @visibleForTesting
  static List<LinkSuggestion> parseLinkSuggestions(
    String reply, {
    required Set<String> validIds,
    Set<String> excludedIds = const {},
    Map<String, String> titleOf = const {},
  }) {
    final match = RegExp(r'\[[\s\S]*?\]').firstMatch(reply);
    if (match == null) return const [];
    try {
      final list = jsonDecode(match.group(0)!) as List;
      final out = <LinkSuggestion>[];
      final seen = <String>{};
      for (final item in list) {
        if (item is! Map) continue;
        final id = (item['noteId'] ?? '').toString().trim();
        if (id.isEmpty || !validIds.contains(id)) continue;
        if (excludedIds.contains(id) || seen.contains(id)) continue;
        seen.add(id);
        final reason = (item['reason'] as String?)?.trim();
        out.add(LinkSuggestion(
          noteId: id,
          title: titleOf[id] ?? '',
          reason: reason,
        ));
      }
      return out;
    } catch (_) {
      return const [];
    }
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

  // ---------------------------------------------------------------------------
  // 知识星图：多跳遍历（阶段四）
  // ---------------------------------------------------------------------------

  /// 从 [startNoteId] 出发做 BFS，返回 [hops] 跳内的可达路径。
  ///
  /// 返回每条路径的笔记 id 序列（含起点），按跳数升序。`visited` 集合保证
  /// 环路不会导致无限循环（A→B→A 只保留最短路径）。
  ///
  /// 一次取全部关联后在内存建邻接表，避免逐跳查库。
  Future<List<GraphPath>> traverse(
    String startNoteId, {
    int hops = 2,
    int maxPaths = 50,
  }) async {
    if (hops <= 0) return const [];

    final List<NoteLink> links;
    try {
      links = await NoteStore.instance.allLinks();
    } catch (e) {
      AiLogger.logWarning('星图遍历读取关联失败: $e');
      return const [];
    }
    if (links.isEmpty) return const [];

    final adjacency = <String, Set<String>>{};
    for (final l in links) {
      adjacency.putIfAbsent(l.sourceNoteId, () => {}).add(l.targetNoteId);
      // 无向遍历：关联双向可见，遍历时也双向可达
      adjacency.putIfAbsent(l.targetNoteId, () => {}).add(l.sourceNoteId);
    }

    final results = <GraphPath>[];
    final visited = <String>{startNoteId};
    // 队列元素：当前路径
    var frontier = <List<String>>[
      [startNoteId]
    ];

    for (var depth = 1; depth <= hops; depth++) {
      final next = <List<String>>[];
      for (final path in frontier) {
        final current = path.last;
        for (final neighbor in adjacency[current] ?? const <String>{}) {
          if (visited.contains(neighbor)) continue;
          visited.add(neighbor);
          final newPath = [...path, neighbor];
          results.add(GraphPath(noteIds: newPath, hops: depth));
          next.add(newPath);
          if (results.length >= maxPaths) break;
        }
        if (results.length >= maxPaths) break;
      }
      if (results.length >= maxPaths || next.isEmpty) break;
      frontier = next;
    }

    return results;
  }

  /// 带星图扩展的检索。
  ///
  /// 先 FTS 命中，再把每个命中沿关联扩展 [graphHops] 跳，把邻居笔记也纳入
  /// 上下文——这样问「豆浆机坏了」命中延保笔记后，同订单/同产品的关联笔记
  /// 也会被带进来。
  Future<List<KbFragment>> retrieveWithGraph(
    String query, {
    int limit = 5,
    int graphHops = 1,
  }) async {
    final direct = await retrieve(query, limit: limit);
    if (direct.isEmpty || graphHops <= 0) return direct;

    final directIds = direct.map((f) => f.noteId).toSet();
    final extra = <KbFragment>[];
    for (final f in direct) {
      final paths = await traverse(f.noteId, hops: graphHops);
      for (final p in paths) {
        final id = p.noteIds.last;
        if (directIds.contains(id)) continue;
        if (extra.any((e) => e.noteId == id)) continue;
        final note = await NoteStore.instance.noteById(id);
        if (note == null || note.isDeleted) continue;
        final md = _notePlainText(note.deltaJson);
        var creds = const <String>[];
        try {
          creds = (await NoteStore.instance.db.credentialsForNote(id))
              .map((a) => a.filename ?? a.localPath.split('/').last)
              .toList();
        } catch (_) {}
        extra.add(KbFragment(
          noteId: id,
          title: note.title,
          snippet: _relevantSnippet(md, query),
          assetCategory: note.assetCategory,
          assetExpiryDate: note.assetExpiryDate,
          credentialFiles: creds,
        ));
      }
    }
    return [...direct, ...extra];
  }

  /// 问答。检索命中则交给 LLM 基于片段作答并附引用；无命中则明确告知
  /// 无相关笔记，**不伪造答案**。
  ///
  /// 走共享 [AgentLoop]，注入三个工具：`notebook_search`（本服务 retrieve）、
  /// `web_search` / `scrape`（[WebSearchService]）。这样用户问笔记里没有的内容
  /// 时，模型可自行降级到联网检索。
  /// 针对指定目标笔记或全库检索提问。
  ///
  /// 若提供 [targetNotes]，则直接提取其全文作为核心上下文，跳过 800 字片断截断，
  /// 同时依然保留 [kbTools]（可根据需要 cross-reference 或联网）。
  /// 若 [targetNotes] 为空，则走原有的 FTS5 + 星图扩展链路。
  Future<KbAnswer> ask(
    String question, {
    int limit = 5,
    int graphHops = 1,
    List<Note>? targetNotes,
  }) async {
    final trimmed = question.trim();
    if (trimmed.isEmpty) {
      return const KbAnswer.noMatch('请输入问题。');
    }

    final String initialPrompt;
    final List<KbCitation> citations;
    final bool usedGraph;
    final List<String> graphIds;

    if (targetNotes != null && targetNotes.isNotEmpty) {
      citations = targetNotes
          .map((n) => KbCitation(noteId: n.id, title: n.title))
          .toList();
      usedGraph = false;
      graphIds = const [];

      final credentialMap = <String, List<String>>{};
      for (final note in targetNotes) {
        try {
          final creds = await NoteStore.instance.db.credentialsForNote(note.id);
          final files = creds
              .map((a) => a.filename ?? a.localPath.split('/').last)
              .toList();
          if (files.isNotEmpty) {
            credentialMap[note.id] = files;
          }
        } catch (_) {}
      }

      initialPrompt = buildTargetPrompt(
        targetNotes: targetNotes,
        question: trimmed,
        credentialMap: credentialMap,
      );
    } else {
      // FTS 直接命中 + 沿星图扩展邻居（阶段四）：问「豆浆机坏了」命中延保笔记后，
      // 同订单/同产品的关联笔记也会被带进上下文。
      final direct = await retrieve(trimmed, limit: limit);
      if (direct.isEmpty) {
        return const KbAnswer.noMatch(
          '你的笔记本里没有与这个问题相关的记录。可以换个说法，或到「AI 咨询与检索」里联网查询。',
        );
      }
      final directIds = direct.map((f) => f.noteId).toSet();
      final fragments = graphHops > 0
          ? await retrieveWithGraph(trimmed, limit: limit, graphHops: graphHops)
          : direct;
      graphIds = fragments
          .map((f) => f.noteId)
          .where((id) => !directIds.contains(id))
          .toList();

      final context = _buildContext(fragments);
      initialPrompt = '以下是我笔记本里检索到的相关记录：\n\n$context\n\n'
          '我的问题：$trimmed';
      citations = fragments
          .map((f) => KbCitation(noteId: f.noteId, title: f.title))
          .toList();
      usedGraph = graphIds.isNotEmpty;
    }

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
        citations: citations,
        usedGraph: usedGraph,
        graphNoteIds: graphIds,
      );
    } catch (e) {
      AiLogger.logError('笔记本问答失败: $e');
      return KbAnswer.failure('生成回答时出错：$e');
    }
  }

  /// 单篇目标笔记全文的最大字符预算，防止单次 prompt 超出 token 上限。
  static const int _maxTargetNoteLength = 30000;

  /// 构建目标笔记的提问 prompt。
  @visibleForTesting
  static String buildTargetPrompt({
    required List<Note> targetNotes,
    required String question,
    Map<String, List<String>> credentialMap = const {},
  }) {
    final targetBuffer = StringBuffer();
    for (var i = 0; i < targetNotes.length; i++) {
      final note = targetNotes[i];
      var body = _notePlainText(note.deltaJson);
      if (body.length > _maxTargetNoteLength) {
        body =
            '${body.substring(0, _maxTargetNoteLength)}\n[...注意：该笔记内容过长，已截取前 $_maxTargetNoteLength 字符...]';
      }
      targetBuffer.writeln('【选定目标笔记 ${i + 1}】标题：${note.title}');
      if (note.assetCategory != null) {
        targetBuffer.writeln('  资产类别：${note.assetCategory}');
      }
      if (note.assetExpiryDate != null) {
        targetBuffer.writeln('  到期日：${_fmtDate(note.assetExpiryDate!)}');
      }
      final creds = credentialMap[note.id] ?? const [];
      if (creds.isNotEmpty) {
        targetBuffer.writeln('  凭证附件：${creds.join('、')}');
      }
      targetBuffer.writeln('  全文内容：\n$body');
      targetBuffer.writeln();
    }

    return '用户已选定以下具体笔记作为本次问答的目标对象：\n\n'
        '${targetBuffer.toString()}'
        '用户提问或分析要求：$question\n\n'
        '请针对上述选定的笔记内容进行深度处理与回答（例如归纳总结、提取业务流程、撰写使用指南、指出逻辑疑点等）。'
        '若分析中需要对比参考其他笔记或联网检索验证外部事实，可使用提供的工具。';
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
才可以调用联网工具。调用工具时严格输出且仅输出如下 JSON 代码块或 <tool_call> 标签：

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

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @visibleForTesting
  String debugBuildContext(List<KbFragment> fragments) => _buildContext(fragments);
}

/// 一条 AI 建议的关联（尚未落库，待用户确认）。
class LinkSuggestion {
  final String noteId;
  final String title;
  final String? reason;

  const LinkSuggestion({
    required this.noteId,
    required this.title,
    this.reason,
  });

  @override
  String toString() => 'LinkSuggestion($noteId, $title, $reason)';
}

/// 星图上的一条可达路径（含起点），用于回答中标注"经过了哪些跳"。
class GraphPath {
  final List<String> noteIds;
  final int hops;

  const GraphPath({required this.noteIds, required this.hops});

  String get start => noteIds.first;
  String get end => noteIds.last;

  @override
  String toString() => 'GraphPath(${noteIds.join(' → ')}, $hops hop)';
}
