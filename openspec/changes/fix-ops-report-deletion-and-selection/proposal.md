## Why

在「磐石运维工具」的「报告中心」中，左侧历史报告列表的单项删除操作目前存在严重的状态与交互缺陷：
1. 点击删除图标时无任何二次确认弹窗与删除成功反馈（SnackBar），破坏性操作无防护；
2. 当删除当前选中的报告时，界面未正确清理选区与文本控制器（若列表中无剩余报告，当前报告对象仍滞留并持续渲染在右侧编辑与预览区）；
3. 若报告来源于 Excel 生成跳转，外层父组件的 `_pendingReport` 状态未在消费或删除后释放，导致后续刷新始终被强制还原回该报告；
4. 伴随发现：数据库 `reports` 表缺少 `markdown_content`（或 `sections`）字段持久化，历史报告重新选中时分段内容丢失为空。

## What Changes

- **报告删除交互防护与操作反馈**：
  - 点击左侧报告列表项的删除按钮时，弹出 `AlertDialog` 二次确认弹窗提示「确定要删除报告「xxx」吗？此操作无法撤销。」；
  - 确认后执行物理删除，并在操作完成后通过 `ScaffoldMessenger` 提示「报告已删除」；
  - 取消则不执行任何操作。
- **删除后选区联动与空状态退避**：
  - 若被删除的报告正是当前正在编辑/浏览的报告：
    - 若列表中仍有其他报告，自动切换选中并加载剩余报告的第一项；
    - 若列表中已无报告，将 `_currentReport` 置为 `null`，并清空标题与内容输入控制器，右侧展示「请选择或新建一份报告」空状态提示；
  - 若被删除的报告并非当前选中的报告，保持当前选中的报告与编辑区不变，仅从列表中移除该项。
- **释放初始报告挂载态（`_pendingReport`）**：
  - 报告被保存或删除后，支持清理从 Excel 导入带来的挂载报告引用，避免后续刷新再度强刷。
- **报告完整内容持久化与恢复**：
  - 在 `reports` 表增加 `markdown_content` / `sections_json` 字段支持，确保保存的 Markdown 分段与正文能够正确持久化与重新加载回填。

## Capabilities

### New Capabilities
<!-- 无新增顶级 capability -->

### Modified Capabilities
- `ops-tool`: 修订「多源运营报告生成、编辑与分发」中报告中心的删除防护、选区退避与持久化回填要求。

## Impact

- **涉及代码**：
  - `lib/tools/ops_tool/ui/ops_report_editor_view.dart`（删除确认、选区退避、提示反馈、控制器同步）
  - `lib/tools/ops_tool/ui/ops_tool_main_page.dart`（`_pendingReport` 消费与清理）
  - `lib/tools/ops_tool/database/ops_database.dart` 与 `lib/tools/ops_tool/models/ops_models.dart`（报告内容序列化存储与加载）
- **数据兼容**：`ops_tool.db` 中 `reports` 表做平滑字段补齐或序列化支持，不破坏存量库。
- **测试**：在 `test/ops_tool_test.dart` / 相关 UI 自动化测试中补齐删除确认、空状态退避与内容保存加载的用例。
