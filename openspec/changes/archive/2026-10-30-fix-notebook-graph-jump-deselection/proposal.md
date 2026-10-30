# Proposal: 修复知识星图与问答引用跳转导致的笔记闪退置空问题

## Why

在知识星图（Knowledge Graph）中点击节点或在 AI 问答中点击引用卡片跳转到笔记时，主编辑窗口中的目标笔记“一闪而过”，随后立即退回未选中空态（显示“选择或创建一条笔记开始记录”）。

根本原因是 `_openNoteById` 仅设置了 `_selectedNote = note`，未同步切换左侧导航栏的笔记本筛选条件。紧接着触发的 `_refresh()` 基于旧的筛选条件查询笔记列表，目标笔记不在该列表中，导致其底部的保护逻辑误判定该笔记已被移除，强行将 `_selectedNote` 置为 `null`。

## What Changes

- **导航上下文联动切换**：在 `_openNoteById` 中解析目标笔记的 `notebookId` 及对应的 `stack`，自动将侧边栏选中项切换到目标笔记本（若无归属笔记本则切换至“全部笔记”），并清空可能生效的标签过滤（`_selectedTagId = null`）和搜索词过滤（`_searchQuery = ''`）。
- **刷新后持久化选中守护**：在 `_refresh()` 重新获取目标笔记本的笔记列表后，确保 `_selectedNote` 稳定指向目标笔记，中间列表栏与主编辑窗口保持选中高亮。
- **防止误置空防护**：改进 `_refresh()` 内部对 `_selectedNote` 的列表匹配检查，避免在异步导航过渡期间误杀刚选中的笔记。

## Capabilities

### Modified Capabilities
- `notebook-tool`: 规范从知识星图或 AI 问答跨分类跳转笔记时的导航上下文联动切换与稳定选中规范。

## Impact

- **UI 页面**：修改 `lib/tools/notebook/ui/notebook_page.dart` 中的 `_openNoteById` 与 `_refresh`。
- **测试**：在 `test/` 下补充针对跳转上下文切换与选中维持的验证测试。
