## Why

`ToolCategory.build`（"包与构建"）在 2026-09-16 的 `merge-clean-builds-into-slimmer` 合并后只剩 `kma-package`（KMA 包生成）一个工具，那次变更的 tasks.md 把"分类空置问题"记成了后续事项；现在该收尾了。KMA 包生成已不再使用：工具本身不写任何持久化配置（全盘无 `kma json`）、磁盘上不存在任何 `.kma` 产物、代码库内零引用，却拖着约 3500 行只服务它的代码和一个明文提交的第三方翻译 API Key。

## What Changes

- **BREAKING**：从 `ToolRegistry` 移除 `kma-package`（KMA 包生成）工具及其页面。
- **BREAKING**：移除 `ToolCategory.build` 枚举值。移除后该分类被完全删除而非留空——留着它会让活动栏出现一个点进去什么都没有的入口（`test/frequently_used_tools_test.dart` 的"每个分类至少一个工具"正是守这件事的）。
- **BREAKING**：删除随工具的页面与只被它引用的组件：`lib/kma_package_tool.dart`、`lib/utils/kma_package_util.dart`、`lib/components/{app_info_form, language_selector, shortcut_input, file_path_selector, password_display, rate_limit_config, translation_config, compress_kma, extract_kma}.dart`。
- `removedToolRedirects` **不**新增 `kma-package` 条目。KMA 打包没有功能承接者，把它指向 `smart-disk-slimmer` 等于把用户骗去磁盘清理；已验证代码路径对已移除标识优雅降级（初始工具选择跳过、常用软件过滤不渲染），不会出现点不开的条目。
- `pubspec.yaml` 的 `encrypt` 依赖与 `settings_store.dart` 中"上限由工具总数决定（16 个）"的过时注释均**不在**本变更范围（见 design.md）。

## Capabilities

### New Capabilities

（无。本变更不引入新能力，只移除。）

### Modified Capabilities

- `app-shell`: 分类分组 scenario 的示例分类"包与构建"随枚举值一同消失，需改为活着的分类；同时显式记录"移除无功能承接者的工具时不加重定向"这一语义，与 clean-builds 有承接者的既有规则并列。

## Impact

- **代码**：删除上述 11 个文件（约 3500 行）；`lib/tools/tool_definition.dart`（删 `ToolCategory.build` 及枚举注释中对应的分类叙述）；`lib/tools/registry.dart`（删 import、`KmaPackageToolDefinition`、注册表条目与"包与构建"分组注释）；`README.md:26` 删除 KMA 工具表格行。
- **分类**：`ToolCategory` 由 8 项减为 7 项。`privacy` 仍独立入口，其余 6 项全部非空。
- **最近使用 / 常用软件**：`getRecentToolIds()` 与 `getMostUsedToolIds()` 对未注册标识已有降级路径，历史 `kma-package` 记录既不渲染也不报错；`toolUsageCounts` 可能残留一个计数，无害。
- **测试**：`test/frequently_used_tools_test.dart` 的"每个分类至少一个工具"随枚举值删除自然变绿（若先删工具后删枚举会短暂转红，属删除顺序问题）；无其他测试引用 `kma-package` 或那 9 个组件类。
- **依赖**：`encrypt` 在 lib/ 内删除后零引用，但本变更不从 pubspec 移除（避免动 `pubspec.lock`）。
- **安全**：明文百度翻译 API Key（`kma_package_util.dart:254`）随文件删除从工作区消失，但**仍在 git history 中**——本变更不 remediate 历史泄露，是否轮换/改写密钥是独立决定。
- **数据**：无用户数据需要迁移（工具不写配置，磁盘无 `.kma` 产物）。
