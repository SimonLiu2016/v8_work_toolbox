## Context

在 AI 短视频工坊中，用户可以通过 `NovelSelectorDialog` 浏览本地小说库（`NovelRepository`）并选取整部小说或特定章节。其返回结果为 `NovelSelectionResult` 数据结构。

目前存在的断点与隐患包括：
1. `NovelSelectorDialog` 为了配合 `IdeaIncubatorPanel` 的后台异步任务机制，在确认时退出的 `NovelSelectionResult.combinedText` 恒为空字符串 `''`；
2. `WritersRoomDialog`（编剧研讨室）是前台即时工作台，收到 `NovelSelectionResult` 后直接取 `result.combinedText`，导致 `_novelText` 为空且判断失败，既未读取本地章节文本，也没有任何 UI 反馈，使窗口关闭后如同软件假死失灵；
3. `AiConstraintEngine.extractWritersRoomMaster` 直接将未截断的 `novelText` 拼接至 Prompt 中，缺少长文本安全采样保护，面对全本小说存在上下文溢出隐患。

## Goals / Non-Goals

**Goals:**
- 在 `NovelSelectionResult` 模型上封装统一的异步正文提取能力 `loadCombinedText()`，自动解析整本/指定章节并合并格式化正文。
- 在 `WritersRoomDialog` 中实现正文自愈提取与全流程加载状态呈现（“正在从本地小说库载入《XXX》章节正文...”）。
- 对所选小说章节内容为空的边缘情况提供明确的 SnackBar 防御提示与状态复位，杜绝静默失败。
- 在 `AiConstraintEngine.extractWritersRoomMaster` 中接入 `sampleNovelTextForContext` 智能窗口采样机制，限制在 35,000 字符预算内。

**Non-Goals:**
- 不破坏 `IdeaIncubatorPanel` 现有的后台流式任务提交模式。
- 不修改小说爬虫与小说数据库存储结构。

## Decisions

### 1. 在 `NovelSelectionResult` 封装 `loadCombinedText()` 方法
- **设计**：
  ```dart
  Future<String> loadCombinedText() async {
    if (combinedText.trim().isNotEmpty) return combinedText;
    if (novel.id.isEmpty) return '';
    final repo = NovelRepository.instance;
    var indices = selectedChapterIndices;
    if (indices.isEmpty) {
      final chs = await repo.getChapterIndices(novel.id);
      indices = chs.map((c) => c.chapterIndex).toList();
    }
    final sb = StringBuffer();
    for (final idx in indices) {
      final ch = await repo.getChapter(novel.id, idx);
      if (ch != null && ch.content.trim().isNotEmpty) {
        sb.writeln('=== ${ch.title} ===');
        sb.writeln(ch.content.trim());
        sb.writeln();
      }
    }
    return sb.toString().trim();
  }
  ```
- **理由**：内聚度高。`NovelSelectionResult` 持有 `novel` 与 `selectedChapterIndices`，理应具备产出完整合并文本的自愈能力；既保留了弹窗秒退的轻快响应，又使任何前台消费方无需重复编写章节读取循环。

### 2. 编剧研讨室完整加载状态与错误引导
- **设计**：
  1. 弹窗返回后，先更新标题并设置 `_isAnalyzing = true; _statusMessage = '正在从本地小说库载入《${result.novel.title}》章节正文...';`；
  2. 调用 `await result.loadCombinedText()`；
  3. 若返回文本为空：提示 `SnackBar('《${result.novel.title}》暂无章节正文，请先在小说管理器中下载或导入正文')`，并将 `_isAnalyzing` 复位为 `false`；
  4. 若文本有效：更新 `_novelText`，立即推进调用 `_runMacroAnalysis()`。
- **理由**：彻底消除无响应问题，给创作者清晰的加载预期与排错指引。

### 3. 复用成熟的 `sampleNovelTextForContext` 采样机制
- **设计**：在 `AiConstraintEngine.extractWritersRoomMaster` 中增加：
  ```dart
  final cleanText = sampleNovelTextForContext(novelText);
  ```
- **理由**：与 `extractNovelMaster` 和 `segmentNovelEpisodes` 保持一致，保留开头铺垫、结尾终局与中间 5 个关键剧情滑动窗口，既保证宏观故事弧线的完整度，又避免超出模型最大 Token 上限。

## Risks / Trade-offs

- **[章节过多时读取耗时]** → 本地章节为独立原子文件读取，数百章读取耗时在几十毫秒级，且在后台 `async` 执行配合转圈状态提示，不会卡顿 UI。
