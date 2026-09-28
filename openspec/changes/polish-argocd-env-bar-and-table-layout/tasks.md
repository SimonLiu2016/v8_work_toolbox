## 1. 合并环境标签与详情卡为单行条

- [ ] 1.1 `_envChip` 内部改为 `Row`：左段 `Expanded(Column(...))` 放名称 + 模式徽章 + 信息概要（GitLab URL / 路径 / 频率 / 状态），右段固定放编辑环境按钮 + Switch + 删除 ✕
- [ ] 1.2 删除独立的详情卡 `Container` 块（build 方法中 `if (env != null) ...[...]` 那段）
- [ ] 1.3 信息概要用 `Text(overflow: TextOverflow.ellipsis)`，窄窗口截断不溢出
- [ ] 1.4 多环境仍用 `Wrap` 排列合并后的条

## 2. Tag 配置表表头与列宽

- [ ] 2.1 表头 6 列字号从 `AppTheme.fontCaption` 改为 `AppTheme.fontBodySecondary`
- [ ] 2.2 列宽从全 `FixedColumnWidth` 改为 `FlexColumnWidth(2)` ×3 + `IntrinsicColumnWidth()` ×3
- [ ] 2.3 确认移除 `IntrinsicWidth`（上一轮已删，不重新引入）

## 3. 验证与部署

- [ ] 3.1 `flutter analyze --no-fatal-infos` 保持 0 errors / 0 warnings
- [ ] 3.2 `flutter test test/ops_tool_test.dart` 全绿
- [ ] 3.3 构建部署，实机确认：环境单行条 + 列宽缩放 + 表头可读
