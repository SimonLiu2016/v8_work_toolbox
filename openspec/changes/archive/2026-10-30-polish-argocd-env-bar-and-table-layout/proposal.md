## Why

ArgoCD 监控页的环境标签与详情卡分成两个独立区块，信息密度低且占据过多纵向空间；Tag 列表表头字号过小、6 列全部 `FixedColumnWidth` 合计 944px 不随窗口缩放——在 1200px 窗口下右侧留白 256px，在更窄窗口下则溢出。

## What Changes

- **合并环境标签与详情卡为单行条**：环境名称、模式徽章、GitLab URL / 路径 / 频率 / 状态靠左；编辑环境按钮、启用/禁用 Switch、删除按钮靠右。选中状态以背景色区分。多环境时仍以 Wrap 排列。
- **表头字号放大**：从 `AppTheme.fontCaption` 改为 `AppTheme.fontBodySecondary`。
- **列宽改为弹性 + 固定混用**：项目名、当前 Tag、目标 Tag 三列用 `FlexColumnWidth` 随窗口缩放；关闭弹窗提醒、状态、启用三列用 `IntrinsicColumnWidth` 贴合内容宽度。

## Capabilities

### New Capabilities

<!-- 无新增能力。 -->

### Modified Capabilities

- `ops-tool`: 修订「编辑环境的入口唯一」场景——环境管理操作（编辑/启停/删除）与环境信息概要展示 SHALL 合并为单行，不得分成两个独立区块。Tag 配置表的列宽 SHALL 随窗口宽度弹性缩放。

## Impact

- **代码**：`lib/tools/ops_tool/ui/ops_devops_view.dart`（`_envChip` 合并详情信息、`_buildTagTable` 改列宽、表头字号）。
- **不影响**：数据层、GitLab 客户端、路径统一、凭据存储。
- **依赖**：无新增。
