## Why

V8WorkToolbox 的本地存储路径解析存在三套并行策略，导致同一份设计承诺在实现层分裂：`integrate-fs-ops-tool` 的 proposal 既写入「复用已有全局统一 AI 配置与 Keychain 密钥服务」，又写明运维数据库落在「`~/Library/Application Support/V8WorkToolbox/ops_tool/`」——但前者由 `AiConfigStore` 用硬编码 `HOME` 拼接解析，后者由 `OpsDatabase` 用 `getApplicationSupportDirectory()` 解析。两策略在应用被授予文件访问授权（沙盒化）时行为分叉：硬编码策略原地不动，`getApplicationSupportDirectory()` 被重定向到带 bundle id 的目录，运维数据库、笔记附件整体失联，而笔记主库走 drift 的 `getDatabasesPath()`（落在 `~/Documents/`）完全不受影响——用户看到笔记都在，误以为一切正常。

该分叉已在 `fix-argocd-service-list-and-unsandbox-app` 中通过移除文件授权临时纠正，但根因（缺少单一定义处）未拆除：12 个模块各自解析路径，其中 2 个用 `getApplicationSupportDirectory()`、9 个用硬编码拼接、1 个用 drift 默认目录。只要再有新模块选错策略，或文件授权被重新加回，分裂会复发。

## What Changes

- **引入单一路径源**：新增 `lib/services/app_paths.dart`，以 `AppPaths.root` 为唯一起点，导出 AI 配置、密码库与 DEK、应用设置、运维工具数据库、笔记附件、阅读器配置、隐私空间媒体、资讯缓存等全部本地数据路径；每个路径带一句注释说明归属模块。
- **12 个模块改调单点**：`ai_config_store`、`settings_store`、`vault_store`、`vault_file_store`、`kek_manager`、`legacy_importer`、`scheduled_news_service`、`ai_assistant_service`、`note_store`、`ops_database`、`private_storage_manager`、`reader_config_store` 全部改为从 `AppPaths` 取路径，不再自行拼接或调用 `getApplicationSupportDirectory()`。
- **笔记主库纳入统一路径**：`note_database.dart` 的 `SqfliteQueryExecutor.inDatabaseFolder(path: 'notebook.db')` 改为显式指向 `AppPaths.notebookDb`，使 44.6M 的 `~/Documents/notebook.db` 迁入应用支持目录，消除第三套策略。**BREAKING**：需一次性迁移该文件，迁移完成前旧位置保留不删。
- **保留 `customRootDir` 测试钩子语义**：`AiConfigStore.init({Directory? customRootDir})`、`AssetReminderService.init({Directory? customRootDir})`、`PrivateStorageManager.init({Directory? customRoot})` 等既有测试注入点行为不变，仅默认值来源从各自拼接改为 `AppPaths`。
- **根路径解析策略固定为「跟随系统 API + 允许测试覆写」**：`AppPaths.root` 在 macOS 上等价于 `~/Library/Application Support/V8WorkToolbox/`，通过 `getApplicationSupportDirectory()` 取得（而非硬编码 HOME），并提供 `@visibleForTesting` 的 override；同时补一条回归测试，断言所有导出的子路径都以 `root` 为前缀。

## Capabilities

### New Capabilities

<!-- 无新增能力：本 change 只统一本地存储位置的解析方式，不改变对外可观察行为。 -->

### Modified Capabilities

- `ops-tool`: 修订「本地数据的应用支持目录唯一」要求——全部本地数据 MUST 经由同一路径源派生，任一模块 MUST NOT 自行拼接或调用平台目录 API；新增「路径源单一性可验证」的回归要求。

## Impact

- **新增**：`lib/services/app_paths.dart`（单一定义处）。
- **改动**：上述 12 个模块的路径解析代码，以及 `lib/tools/notebook/note_database.dart` 的连接构造。
- **数据迁移**：`~/Documents/notebook.db`（44.6M）→ `~/Library/Application Support/V8WorkToolbox/notebook.db`，一次性 `mv`，迁移后校验页数/行数一致；旧文件保留至用户确认。
- **不迁移**：各 JSON/DB 文件本就位于 `AppPaths.root` 下（`ai_config.json`、`.dek`、`.secrets.bin`、`ops_tool/ops_tool.db`、`notebook_attachments/`、`PrivateMedia/` 等），无需移动；仅解析方式改变。
- **测试**：既有 `NoteDatabase.forTesting`、`AssetReminderService(customRootDir:)`、`OpsDatabase.debugOpenOverride` 等注入点保持可用；新增路径单点回归测试。
- **依赖**：无新增第三方依赖。
