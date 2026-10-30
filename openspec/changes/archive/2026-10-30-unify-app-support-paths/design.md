## Context

参见 `proposal.md - Why`。

现状实测（2026-09-22，去沙盒后的应用）：

```
~/Library/Application Support/V8WorkToolbox/          ← A 类硬编码路径（9 个模块）
    ai_config.json (2.8K)        ai_config_store.dart:317   HOME 拼接
    .dek (50B)                   kek_manager.dart:43        HOME 拼接
    .secrets.bin / app.json      vault_store / settings_store
    ops_tool/ops_tool.db         ops_database.dart:55       getApplicationSupportDirectory()
    notebook_attachments/        note_store.dart:28         getApplicationSupportDirectory()
    PrivateMedia/ / config/ / logs/

~/Documents/notebook.db (44.6M)                        ← C 类 drift 默认目录
    note_database.dart:503       SqfliteQueryExecutor.inDatabaseFolder('notebook.db')
```

12 个调用 `getApplicationSupportDirectory()` 的模块中，只有 `note_store` 与 `ops_database` 真正使用其返回值；其余 10 个虽在 import 或相邻代码中出现该方法名，实际路径来自硬编码拼接。`ops_database` 与 `note_store` 正是沙盒化时发生漂移的两个。

## Goals / Non-Goals

**Goals:**
- 建立 `AppPaths` 单点，全部本地数据路径由其派生。
- 12 个模块不再自行拼接目录，也不再直接调用 `getApplicationSupportDirectory()`。
- 笔记主库从 `~/Documents/` 迁入应用支持目录，消除第三套策略。
- 提供回归测试，使「某模块又自己拼路径」这类回退可被自动发现。

**Non-Goals:**
- 不改动数据的格式、加密方案或表结构。
- 不处理 `desktop_multi_window` 子窗口的 arguments 传递或窗口生命周期。
- 不迁移 `~/Library/Application Support/com.v8en.V8WorkToolbox/` 下的残留（已在上一 change 处理完，仅剩空目录）。
- 不引入 `shared_preferences` 等新存储机制。

## Decisions

### 1. `AppPaths` 形态：静态常量 + 异步初始化根目录

- **决策**：`AppPaths` 为抽象 final 类，暴露 `static Directory root`（由 `init()` 异步写入）与一组派生路径的静态 getter（`aiConfigFile`、`opsToolDbFile`、`noteDbFile`、`attachmentsDir`、`privateMediaDir` …）。根目录通过 `getApplicationSupportDirectory()` + 固定子目录名 `V8WorkToolbox` 解析，并提供 `@visibleForTesting static void overrideRootForTesting(Directory)`。
- **原因**：`getApplicationSupportDirectory()` 是异步的，无法在静态字段初始化时取得；改为 `init()` 一次性解析后写入静态字段，读取端保持同步、无需把 12 个模块全部改成异步链。测试需要隔离时用 override 替换根目录，语义与既有 `customRootDir` 钩子一致。
- **为什么不是「全部硬编码 HOME」**：硬编码绕过了系统 API，在非 macOS 平台（Windows/Linux）上路径错误，且无法反映系统级重定向。跟随 `getApplicationSupportDirectory()` 是正确的默认；配合上一 change 已移除的文件授权，macOS 上其返回值即 `~/Library/Application Support/V8WorkToolbox/`。
- **为什么子目录名仍是 `V8WorkToolbox`**：`getApplicationSupportDirectory()` 在 macOS 返回 `~/Library/Application Support/<bundle display name 或 bundle id>`，历史上本项目两种都出现过。显式拼接固定子目录名可使路径与 bundle id 解耦，避免改名再次漂移。

### 2. 各模块改造：保留 `customRootDir`，仅替换默认值来源

- **决策**：`AiConfigStore.init({Directory? customRootDir})` 等方法签名不变，函数体内 `dir = customRootDir ?? AppPaths.root`。私有 `_attachmentsDir`、`_stateFile` 等同样改为从 `AppPaths` 取默认值。
- **原因**：既有测试（`asset_reminder_test`、`private_player_test`、`ops_tool_credentials_ux_test`）依赖这些注入点；改签名会一次性打断多个测试文件。仅替换默认值来源即可达成统一，且改动可逐模块验证。
- **替代方案**：删掉注入点、统一用 `AppPaths.overrideRootForTesting`。放弃：改动面扩散到测试，且 `customRootDir` 表达的是「这一个服务用哪个目录」，比全局 override 更精确。

### 3. 笔记主库迁移：`AppPaths.noteDbFile` + 一次性搬迁

- **决策**：`note_database.dart:501` 的 `LazyDatabase` 改为 `SqfliteQueryExecutor(path: AppPaths.noteDbFile.path)`（先 `ensure` 父目录存在）；并在 `NoteStore.init()` 中加一次性搬迁：若 `AppPaths.noteDbFile` 不存在而 `~/Documents/notebook.db` 存在，则移动并在日志中记录。
- **原因**：44.6M 数据必须留在用户机器上；`mv` 在同一卷内是元数据操作，瞬间完成且无数据复制风险。
- **校验**：搬迁前后比对 `PRAGMA page_count` 与 `PRAGMA user_version`；失败则保留原文件不动并记错误（不阻断启动，与 main() 的 fail-soft 契约一致）。

### 4. 回归测试：单点前缀断言

- **决策**：新增 `test/app_paths_test.dart`，覆写 root 为临时目录后，断言 `AppPaths` 导出的每个路径 `startsWith(root.path)`；并断言 `noteStore` / `opsDatabase` 等模块在注入 root 后落盘位置随之改变（用最小的 fake `Database` 或仅验证路径字符串）。
- **原因**：spec 的「路径源单一性可验证」需要一条能抓住回退的测试。前缀断言成本极低，且任何模块重新引入 `p.join(home, ...)` 都会因前缀不符而暴露。

## Risks / Trade-offs

- **[Risk] `AppPaths.root` 未初始化就被读取（静态字段为 null）**
  → Mitigation: `root` 的 getter 在未初始化时抛出带说明的 `StateError`（指明应先在 main() 的 `WindowServices.initFor` 中调用 `AppPaths.init()`），而非静默返回 null 导致路径变成 `null/xxx`。测试与子窗口入口统一走 `WindowServices`，天然覆盖。

- **[Risk] 笔记主库搬迁中断电/崩溃导致数据损毁**
  → Mitigation: `mv` 前先 `cp` 到目标再校验校验和，成功后删源；或退一步仅 `cp` 保留双份，由用户手动删。默认取前者（同卷 `mv` 实为 rename，原子性足够），但实现时先做存在性判断，避免覆盖已有目标。

- **[Risk] `~/Documents/notebook.db` 被外部工具（备份脚本、其他应用）引用**
  → Mitigation: 搬迁后不在源位置留空文件，但在首次启动日志中明确写出新路径；`docs`/`README` 如有提及需同步（当前仓库未见提及）。

- **[Risk] 12 个模块逐个改造期间路径不一致（改了一半）**
  → Mitigation: 按「先建 AppPaths 并提供全部导出 → 再逐模块替换」的顺序，每个模块替换后立即 `flutter analyze` + 跑相关测试；中途不提交半成品状态。

## Migration Plan

1. 新增 `lib/services/app_paths.dart`，导出全部路径并提供 `init()` / `overrideRootForTesting()`。
2. 在 `main()` 的各窗口入口（主窗口 + 子窗口）经由 `WindowServices` 调用 `AppPaths.init()`，确保任何进程形态下 `root` 就绪。
3. 逐模块替换默认路径来源（顺序：`ai_config_store` → `settings_store` → `vault_store` / `vault_file_store` / `kek_manager` / `legacy_importer` → `scheduled_news_service` / `ai_assistant_service` → `reader_config_store` → `private_storage_manager` → `note_store` → `ops_database`），每个模块后跑 `flutter analyze --no-fatal-infos` 与相关测试。
4. 新增 `test/app_paths_test.dart` 前缀断言与最小模块联动断言。
5. `note_store` 加入笔记主库一次性搬迁逻辑；`note_database` 改显式路径。
6. 全量 `flutter test`，对比既有失败清单（13 处环境依赖型 + `evernote_import` 时序波动）。
7. 构建部署：`flutter clean` → `build macos --release` → `codesign -v --strict` → 暂存 → 备份 → 替换 → 校验 AOT 哈希。
8. 启动 app 验证：`~/Documents/notebook.db` 已迁入 `AppPaths.root/notebook.db`，笔记与附件正常；旧位置不再被写入。
9. **回滚**：`/Applications/V8WorkToolbox.app.bak-sandboxed-20260922` 与 `.bak-20260922` 两级备份在位；数据侧搬迁前会先 `cp` 源文件到 `.bak-migrate-paths`。

## Open Questions

- 无。路径导出的完整清单以 12 个模块当前实际写入的文件为准，实现时逐个核对，不预设未出现的路径。
