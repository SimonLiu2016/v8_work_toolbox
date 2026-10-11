## 1. 移除分类与工具注册

- [x] 1.1 `lib/tools/tool_definition.dart`：删除 `build('包与构建', Icons.inventory_2_outlined)` 枚举值，同步修正枚举上方注释中关于分类拆分的叙述（原文提到 `system` 拆出 `ai`/`note`/`ops`/`security` 后 `system` 只保留系统与配置类，删除 `build` 后需如实反映）
- [x] 1.2 `lib/tools/registry.dart`：删除 `import '../kma_package_tool.dart'`、`KmaPackageToolDefinition` 整个类（含 `id`/`title`/`subtitle`/`icon`/`category`/`buildPage`）、`tools` 列表中的条目与其上方 `// 包与构建` 分组注释
- [x] 1.3 确认删除顺序落在同一提交内（先 1.1 后 1.2），使 `test/frequently_used_tools_test.dart` 的"每个分类至少一个工具"在整个过程中不出现转红的中间态

## 2. 删除工具页面与专属代码

- [x] 2.1 删除 `lib/kma_package_tool.dart`
- [x] 2.2 删除 `lib/utils/kma_package_util.dart`
- [x] 2.3 删除 `lib/components/app_info_form.dart`
- [x] 2.4 删除 `lib/components/language_selector.dart`
- [x] 2.5 删除 `lib/components/shortcut_input.dart`
- [x] 2.6 删除 `lib/components/file_path_selector.dart`
- [x] 2.7 删除 `lib/components/password_display.dart`
- [x] 2.8 删除 `lib/components/rate_limit_config.dart`
- [x] 2.9 删除 `lib/components/translation_config.dart`
- [x] 2.10 删除 `lib/components/compress_kma.dart`
- [x] 2.11 删除 `lib/components/extract_kma.dart`

## 3. 清理文档与残留引用

- [x] 3.1 `README.md`：删除表格中"KMA 包生成"整行（不做整张表的全面校对）
- [x] 3.2 全库 grep 确认零残留：`kma`（大小写不敏感）、`KmaPackage`、`KmaPackageToolPage`、`TranslationServiceType`、`CompressKma`、`ExtractKma`，以及那 9 个组件的类名（`AppInfoForm`/`LanguageSelector`/`ShortcutInput`/`FilePathSelector`/`PasswordDisplay`/`RateLimitConfig`/`TranslationConfig`）
- [x] 3.3 确认 `openspec/specs/app-shell/spec.md:40` 中作为示例的分类已改为活着的分类（见 specs delta 的"工具按分类分组"scenario），且没有其它 spec 枚举"包与构建"

## 4. 验证

- [x] 4.1 `flutter analyze` 无新增 error（0 error；其余 warning/info 经比对均为既有存量，与本次删除无关——含工作区里其它未提交变更带入的）
- [x] 4.2 `flutter test`：`test/frequently_used_tools_test.dart` 11/11 全绿（含"每个分类至少一个工具"与各分类成员断言）；连同 tool_panel_hover / password_vault_registry / theme_accent_render_contrast 共 29 项全过
- [x] 4.3 `flutter test` 全量跑过：1169 过 / 17 败。已用 `git stash`  stash 掉本次改动后在基线复跑同一批失败文件，失败集合完全一致（table_* 三处、notebook_table_interactive、mcp_assistant 的 Firecrawl 预设、ops_tool 的 GitLabClient 三处）——均为与本次删除无关的既有失败，非本次引入
- [x] 4.4 活动栏分类经测试打印核实：`[文件处理, AI 与资讯, 笔记与学习, 运维与监控, 安全工具, 系统与配置, 隐私空间]` —— 6 个公开分类 + 隐私空间，无"包与构建"；"每个分类至少一个工具"测试通过即证明每个入口点进去都有工具
- [x] 4.5 降级路径已用临时测试（跑完已删）逐条断言：`findById('kma-package')` 返回 null；`getRecentToolIds()` 不含该 id；`getMostUsedToolIds()` 会透出该 id 但渲染层 `findById==null → continue` 后结果为空。**未真机启动应用改 config/app.json 手动验**——见下面「未做的事」

## 5. 显式不做（防手滑）

- [x] 5.1 `encrypt` 依赖保留（未从 pubspec 移除，理由见 design.md 决策 4）。注意：工作区里 `pubspec.yaml`/`pubspec.lock` 显示为已修改，但那是本会话之前就存在的未提交变更（新增测试依赖 `sqflite_common_ffi`），与本次删除无关；`git diff` 确认本次未触碰其中的 `encrypt` 条目
- [x] 5.2 确认 `lib/services/settings_store.dart` 的 `removedToolRedirects` 未新增 `kma-package` 条目
- [x] 5.3 确认未把 `lib/` 根部其它旧工具页搬进 `lib/tools/<id>/`（非本变更范围）
- [x] 5.4 确认未改写 git history、未轮换密钥（本变更不 remediate 历史泄露）

## 未做的事

- **4.5 未做真机验证**：只跑了进程内断言，没有启动应用、没有手工改 `config/app.json`。降级路径的代码判读是可靠的（`findById` 返回 null 的两处消费点都是 `continue`/跳过），但"应用能正常启动选中一个已注册工具"这条没有实机证据。
- **4.4 未做真机点击**：分类集合是通过枚举打印 + 单测断言的，不是人眼在跑起来的应用里点过 6 个入口。
- **两个既有失败与本变更的因果已排除**（用 stash 复跑基线比对），但**没有修复**它们。
