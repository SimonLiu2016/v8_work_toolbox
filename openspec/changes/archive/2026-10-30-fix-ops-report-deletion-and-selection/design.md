## Context

目前「报告中心」([ops_report_editor_view.dart](file:///Users/simon/ClaudeWorkspace/V8WorkToolbox/lib/tools/ops_tool/ui/ops_report_editor_view.dart)) 承担了 Markdown 报告的手工撰写、AI 研判提炼、HTML 邮件导出与历史报告管理功能。
动机参见 `proposal.md - Why`。

## Goals / Non-Goals

**Goals:**
- 为报告删除操作补充二次确认弹窗（`showDialog`）与操作反馈（`SnackBar`）。
- 建立严密的选区退避逻辑：删除当前报告时正确切换至相邻项或置空；删除唯一报告时展示空状态，清空所有输入控制器。
- 修复 Excel 生成初始报告的状态生命周期，防止初始挂载态无休止重写当前状态。
- 为 `Report` 模型补齐分段数据的序列化（`sections_json`），使历史报告重新被选中时能完整还原其 Markdown 正文。

**Non-Goals:**
- 不重构报告编辑器的整体双栏布局或 Markdown 渲染管线。
- 不引入外部草稿自动保存或复杂的 Undo/Redo 历史栈。

## Decisions

### 1. 采用模态对话框二次确认与 SnackBar 统一反馈
- **决策**：点击垃圾桶图标时，唤起 `AlertDialog`。若确认，调用 `await OpsDatabase.instance.deleteReport(r.id)`，随后在 `context` 触发 `ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('报告已删除')))`。
- **备选方案**：直接滑动删除（Dismissible）或气泡确认（PopupMenu）。
  - *否决理由*：报告包含用户编写与 AI 研判的心血，误触代价极高，且桌面端鼠标操作使用标准模态弹窗体验最为明确。

### 2. 局部状态解耦与选区退避策略 (Selection Fallback)
- **决策**：
  - 在 `_OpsReportEditorViewState` 中引入本地状态标记或可变引用 `Report? _activeInitialReport`，在首次挂载并初始化完成后即置空，后续的 `_refreshReports()` 不再受 `widget.initialReport` 持续强刷绑架。
  - 删除逻辑显式比对 `isDeletingCurrent = (_currentReport?.id == r.id)`：
    - `isDeletingCurrent == true`：若过滤后的剩余列表不为空，`_currentReport = remaining.first` 并调用 `_syncControllers()`；若剩余列表为空，`_currentReport = null`，清空 `_titleCtrl` 和 `_contentCtrl`。
    - `isDeletingCurrent == false`：保留 `_currentReport` 与文本控制器的现有内容不变。

### 3. 数据层增强：`sections_json` 列与平滑迁移
- **决策**：
  - 在 `Report` 的 `toMap()` 中增加 `'sections_json': jsonEncode(sections.map((s) => s.toMap()).toList())`。
  - 在 `Report.fromMap()` 中若存在 `sections_json` 且非空则解析还原；若不存在则兼容旧数据回退为空或默认 custom 分节。
  - 在 `OpsDatabase` 的建表语句补充 `sections_json TEXT` 列，并在 `_initDatabase` 或 upgrade 中以 `ALTER TABLE reports ADD COLUMN sections_json TEXT` 兼容老数据库。

## Risks / Trade-offs

- **[Risk]** 在已有 `ops_tool.db` 中直接读取可能缺少 `sections_json` 列。
  - **Mitigation**: 在 `ops_database.dart` 初始化时对 `reports` 表执行结构检测或在打开时通过 `ALTER TABLE` 补充该列（`catch` 忽略已存在异常）。
- **[Risk]** 在正在编辑未保存修改时，若用户删除了另一份历史报告，不应冲掉当前编辑框中用户刚输入的文字。
  - **Mitigation**: 严格限制仅当删除的是当前选中的报告时才重新同步文本控制器，删除其他报告只刷新左侧 `_reports` 列表。
