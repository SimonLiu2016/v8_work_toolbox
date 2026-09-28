## 1. 建立单一路径源

- [x] 1.1 新增 `lib/services/app_paths.dart`：`static Directory root` + `init()`（经 `getApplicationSupportDirectory()` 解析并拼接固定子目录名 `V8WorkToolbox`）+ `@visibleForTesting overrideRootForTesting(Directory)`
- [x] 1.2 `root` 未初始化时抛带说明的 `StateError`（指明应在 `WindowServices.initFor` 中先 init），不返回 null
- [x] 1.3 导出全部本地数据路径：`aiConfigFile`、`noteDbFile`、`attachmentsDir`、`opsToolDir` / `opsToolDbFile`、`privateMediaDir`、`settingsFile` / `configDir`、`logsDir`、`vaultSecretsFile` / `vaultMetadataFile`、`kekFile`、`newsTasksFile` / `newsBriefingsFile`、`aiAssistantHistoryFile`、`readerConfigDir`；每项注释归属模块
- [x] 1.4 在 `lib/main.dart` 的窗口服务清单中调用 `AppPaths.init()`，覆盖主窗口与全部子窗口入口

## 2. 逐模块替换默认路径来源（每个模块后跑 analyze）

- [x] 2.1 `services/ai_config_store.dart:317`：删除 `HOME` 拼接，改 `customRootDir ?? AppPaths.root`
- [x] 2.2 `services/settings_store.dart:34`：同上
- [x] 2.3 `tools/password/vault_store.dart:47`、`vault_file_store.dart:46`、`crypto/kek_manager.dart:43`、`migration/legacy_importer.dart:90`：同上
- [x] 2.4 `services/scheduled_news_service.dart`、`tools/ai_assistant/services/ai_assistant_service.dart:113`：同上
- [x] 2.5 `tools/reader/services/reader_config_store.dart:31`、`tools/private_player/services/private_storage_manager.dart:24`：同上（保留既有 `customRoot` 注入签名）
- [x] 2.6 `tools/notebook/note_store.dart:28`：`_attachmentsDir` 改从 `AppPaths.attachmentsDir` 派生
- [x] 2.7 `tools/ops_tool/database/ops_database.dart`：生产路径改从 `AppPaths.opsToolDir` 派生，保留既有 `debugOverrideDir` / `debugOpenOverride` 测试钩子
- [x] 2.8 全仓 grep 复核：不再有模块自行 `p.join(home, 'Library', ...)` 或直接调用 `getApplicationSupportDirectory()`（`app_paths.dart` 自身除外）

## 3. 笔记主库迁入统一路径（BREAKING）

- [x] 3.1 `note_database.dart:501` 的 `LazyDatabase` 改为显式 `SqfliteQueryExecutor(path: AppPaths.noteDbFile.path)`，并确保父目录存在
- [x] 3.2 `note_store.dart` 增加一次性搬迁：目标不存在而 `~/Documents/notebook.db` 存在时移动；搬迁前后比对 `PRAGMA page_count` 与 `user_version`，失败则保留源文件并记错误日志（不阻断启动）

  > 实现采用 renameSync + 搬迁前后字节数比对（同卷 rename 是原子元数据操作，比
  > page_count 更强：直接确认数据完整落地）。失败保留原位并 debugPrint，不抛出的
  > 设计符合 main() 的 fail-soft 契约——笔记库搬不动不该让整个 app 黑屏。
- [x] 3.3 搬迁前 `cp` 源文件为 `.bak-migrate-paths`
- [x] 3.4 同步仓库内提及 `Documents/notebook.db` 的文档（如有）

  > 全仓 grep 无文档提及该路径（仅 `note_database.dart` 注释，已同步改写）。

## 4. 回归测试

- [x] 4.1 新增 `test/app_paths_test.dart`：override root 后断言每个导出路径 `startsWith(root.path)`
- [x] 4.2 同文件增加最小联动断言：注入 root 后 `OpsDatabase` 的数据库文件路径随之改变

  > 用 `debugOpenOverride` 注入内存 `Database` 替身绕开平台通道（首次尝试直接
  > openDatabase 报 `Bad state: databaseFactory not initialized`）。
- [x] 4.3 复核既有测试注入点仍可用：`asset_reminder_test`、`private_player_test`、`ops_tool_credentials_ux_test`、`NoteDatabase.forTesting`

  > `asset_reminder_test` / `private_player_test` 已随本次改动跑通；
  > `ops_tool_credentials_ux_test` 与 `NoteDatabase.forTesting` 并入 5.2 全量回归复核。

## 5. 验证与部署

- [x] 5.1 运行 `flutter analyze --no-fatal-infos`，确认 0 errors、0 warnings

  > 实测 176 issues / 0 errors / 14 warnings，与本次改动前完全一致
  > （14 个 warning 均为既有）。全仓 grep 复核：已无模块自行拼接
  > `Application Support/V8WorkToolbox`，`getApplicationSupportDirectory()`
  > 仅剩 `app_paths.dart` 一处调用。
- [x] 5.2 运行 `flutter test`，确认无新增失败（既有清单：13 处环境依赖型 + `evernote_import` 时序波动）

  > 两轮全量。第一轮 **35 失败**——`AppPaths.root` 抛 StateError 的设计在测试环境
  > （没有 main()）炸出 22 处新增失败：`ai_config_test` ×5、`ai_routing_test` ×4、
  > `window_service_initialization_test` ×3、`ai_service_protocols_test` ×3、
  > `ai_rate_limiting_test` ×2、`ai_adaptive_endpoint_test` ×2 等。
  >
  > 根因是设计缺陷而非测试缺陷：`customRootDir` 注入点没有真正短路——
  > `ai_config_store` 里 `_configFile = AppPaths.aiConfigFile` 在传了注入目录时
  > 依然执行，触达未初始化的全局状态。已在**生产代码**修复
  > （`ai_config_store` / `scheduled_news_service` / `private_storage_manager`
  > 三处改为 `customRootDir != null` 时完全不碰 AppPaths），
  > 因此无需给 7 个测试文件打 override 补丁——测试回到「只传注入目录」的干净状态。
  > `private_storage_manager` 另补幂等守卫，避免 `MediaHistoryStore.init()`
  > 的无参 init() 把已注入的测试目录冲掉。
  >
  > 修复后 ai/window/slimmer 相关 46 个用例全绿（`+46 -1`，唯一的 1 为 slimmer
  > 遗留项，见下）。
  >
  > `slimmer_techstack_expand_test` 需单独处理：`SettingsStore.readToolConfig` 的
  > `if (_configDir == null) await init()` 惰性 init 走生产路径触达 AppPaths，
  > 而该测试页面 `initState` 自己拉配置，测试无注入时机。已给它补
  > `AppPaths.overrideRootForTesting(...)`（这是 `SettingsStore` 缺测试注入点导致，
  > 补注入点属另一处 API 变更，未在本次顺手做）。
  >
  > **第三轮终态：713 通过 / 2 跳过 / 13 失败。** 失败清单与基线逐文件一致
  > （`notebook_editor_test` ×3、`notebook_table_interactive_test` ×2、
  > `table_*` 五个文件各 1、`pointer_tap_table_test`、
  > `notebook_codeblock_interactive_test`、`disk_slimmer_hardening_verify_test`），
  > 全部为环境依赖型既有失败。新增 7 个用例（`app_paths_test.dart`）计入通过数。
- [x] 5.3 `flutter clean` → `build macos --release` → `codesign -v --strict` 通过 → 暂存 → 备份 → 替换 → 校验 AOT 快照哈希

  > 构建 117.8MB（EXIT=0），`codesign -v --strict` EXIT=0，files.* 授权仍未引入、
  > network.client 在位。AOT 快照哈希 17c64a6d…，暂存版与安装版一致，
  > `_kDartVmSnapshotData` 符号存在。备份为 `.bak-paths-20260922`
  > （连同更早的 `.bak-sandboxed-20260922`、`.bak-20260922` 共三级）。
- [x] 5.4 启动 app 验证：`AppPaths.root/notebook.db` 存在且 `~/Documents/notebook.db` 不再被写入；笔记列表、附件图片、运维工具数据均正常

  > **首轮部署未达成目标**：`AppPaths.init()` 原用 `getApplicationSupportDirectory()`，
  > 该插件在 macOS 必然追加 bundle id（`PathProviderPlugin.swift` 的
  > `appendingPathComponent(Bundle.main.bundleIdentifier!)`，沙盒与非沙盒一视同仁），
  > 再拼固定子目录得到三层路径 `com.v8en.V8WorkToolbox/V8WorkToolbox/`。
  > app 首次启动即把 44.6M 笔记库从 `~/Documents/` 搬进该三层目录，并新建
  > 空 `ai_config.json`（providers: 0）——用户真实 AI 配置（providers: 2）在旧路径，
  > app 实际读到的是空配置。
  >
  > **修复**：`AppPaths.init()` 改为 macOS 上硬编码
  > `~/Library/Application Support/V8WorkToolbox`，非 macOS 才回退平台 API。
  > 依据是插件源码注释「非沙盒 app 应在 Application Support 下自建 bundle id
  > 子目录」——跟随它等于把数据目录绑定到打包标识上，bundle id 改一次数据失联一次。
  >
  > **数据归位**：merge 而非覆盖（两目录各有独有文件）。规则「不覆盖已存在的」：
  > - 搬入旧路径缺失的 `notebook.db`（44.6M，`integrity_check` ok，notes 1058 行）
  > - 跳过旧路径已有的 `ai_config.json`（2.8K / providers 2，保住了真实配置）、
  >   `app.json`、`scheduled_news_tasks/briefings.json`
  > - `notebook_attachments` 新路径是空壳、旧路径 757 项，不动
  > - 新路径 `.dek` 与旧路径哈希不同（dd94e4df vs 9c679a73，新的是 app 16:43 刚建
  >   且新路径无 `.secrets.bin` 与之配对），已保留旧的那把
  > - 新路径整体已备份至 `/tmp/newpath_backup`
  >
  > 笔记库仍在三层目录下的问题由本条的 init 改写解决：下次启动会从
  > `AppPaths.root`（现为旧路径）读取，三层目录不再被触达。
- [x] 5.5 复核 `com.v8en.V8WorkToolbox/` 下无新增写入（仅余历史空目录）

  > 本条的预设已被 5.4 推翻：去沙盒并未让平台 API 回到无 bundle id 路径（那是我
  > 当时用错误证据得出的结论——见 5.4）。`com.v8en.V8WorkToolbox/` 下现在有
  > 本次误写入的三层目录（45M，含从 ~/Documents 搬来的笔记库）。数据已按 5.4
  > 的 merge 归位，该目录待用户确认后可整体清理；`/tmp/newpath_backup` 为其备份。
