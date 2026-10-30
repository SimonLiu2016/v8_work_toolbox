## 1. 数据模型与持久化增强

- [x] 1.1 在 `Report` 与 `ReportSection` 模型中完善 `sections_json` 的双向序列化与反序列化，支持空值安全回退
- [x] 1.2 在 `OpsDatabase` 中支持 `reports.sections_json` 字段定义与已有数据库的平滑升级补全

## 2. 报告中心删除确认与交互反馈

- [x] 2.1 在 `OpsReportEditorView` 中为删除按钮添加模态二次确认弹窗 (`AlertDialog`)，取消时中断操作
- [x] 2.2 确认删除后执行物理删除，并在完成时通过 `ScaffoldMessenger` 弹出「报告已删除」操作反馈

## 3. 选区退避与控制器状态同步

- [x] 3.1 优化 `OpsReportEditorView` 的初始报告消费逻辑，避免 `widget.initialReport` 在后续刷新中无限强刷
- [x] 3.2 完善删除选区退避逻辑：若删除当前选中报告，在有剩余项时自动切换并重载第一项；若已无报告，清空 `_currentReport` 与文本控制器并展示空状态
- [x] 3.3 确保删除列表中其他未选中报告时，不影响当前编辑器的文本输入与光标状态

## 4. 自动化测试与回归验证

- [x] 4.1 编写单元测试覆盖 `Report` 包含 Markdown `sections` 的持久化存取与反序列化
- [x] 4.2 编写 Widget 测试覆盖报告删除二次确认弹窗、取消操作、确认后选区退避至下一项及退避至空状态全流程
