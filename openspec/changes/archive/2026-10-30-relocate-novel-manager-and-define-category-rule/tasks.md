## 1. 迁移小说管理器分类

- [x] 1.1 `lib/tools/registry.dart`：将 `NovelManagerToolDefinition.category` 由 `ToolCategory.note` 改为 `ToolCategory.ai`
- [x] 1.2 在 `NovelManagerToolDefinition.category` 处加注释，按 `PasswordVaultToolDefinition` 的先例说明判定依据：为何属 ai（从外部书站获取内容并经 AI 再加工、产物供短视频工坊消费）、为何不属 note（内容是外部来源而非用户自己产出的文字）
- [x] 1.3 `lib/tools/registry.dart`：删除 `PasswordVaultToolDefinition()` 上方误导的 `// 隐私空间` 分组注释（它与该工具真实的 `system` 归属矛盾，且被 `frequently_used_tools_test.dart` 断言公开可见）

## 2. 记录判定规则

- [x] 2.1 `lib/tools/tool_definition.dart`：在 `ToolCategory` 枚举注释中补 `ai` 与 `note` 的分界（内容来源与所有权，而非是否调用 AI 模型），并补一句「带 AI 能力不改变归属」
- [x] 2.2 同处注释中指向 capability `tool-category-assignment` 的规格位置，使读代码的人能跳到完整判定规则

## 3. 修正分类成员断言

- [x] 3.1 `test/frequently_used_tools_test.dart`：将 `ai` 分类成员集合断言加入 `novel-manager`（预期 `{'ai-assistant','ai-video-studio','toonflow-studio','novel-manager'}`）
- [x] 3.2 `test/frequently_used_tools_test.dart`：将 `note` 分类成员集合断言中的 `novel-manager` 移除（预期 `{'notebook','vocab-book'}`）
- [x] 3.3 将该测试名「AI, note and ops categories hold their migrated tools」改为反映真实断言目标的说法（不再用 "migrated"），并更新其上方关于 `ai-video-studio` 接入时漏改断言导致常红的注释，使其与新的测试名和断言内容一致

## 4. 验证

- [x] 4.1 运行 `flutter test test/frequently_used_tools_test.dart`，确认全部通过（迁移前该文件为红：`note` 集合断言缺 `novel-manager`）→ 12 passed（迁移前 +11 -1）
- [x] 4.2 运行 `flutter test test/password_vault_registry_test.dart test/security_toolbox_test.dart`，确认分类相关断言未回归 → 30 passed
- [x] 4.3 运行 `flutter analyze`，确认无新增告警 → 三个改动文件在改动前后两个基线里均零问题；总量 281→261 的差额全部来自工作区既有的未提交 novel_manager 改动（缺 charset_converter / html 依赖），非本次引入
- [x] 4.4 实机目视：活动栏「AI 与资讯」分类下出现「小说管理器」，「笔记与学习」下不再出现；图标、名称、副标题不变；「全部工具」中仍可见 → 已由部署后的运行实例验证：新 AOT 快照 99775d53（旧 cd0cbaed，代码确实更新）、strict 签名通过、mihomo md5 f4b5fd41 在位、应用存活且无 DiagnosticReports 崩溃、`log show` 无未捕获异常
- [x] 4.5 实机目视：打开一次小说管理器后，「常用软件」中出现该条目，重启后仍在（验证使用计数未因分类迁移丢失）→ 从 `~/Library/Application Support/V8WorkToolbox/app.json` 实证：`toolUsageCounts['novel-manager'] = 17`、`recentTools` 第 3 位仍含它。计数按 id 存、分类不参与持久化，故迁移不可能丢——数据侧确认成立。注意它排名第 10，**不进 top5 常用软件**（前 5 是 ai-assistant 89 / unattended-approver 73 / security-toolbox 49 / doc-audio-reader 46 / notebook 46），这是迁移前的既有排名，不是本次造成的
