## Why

`file_picker` 10.3.x 的 macOS 端在 Swift 侧强制校验 App Sandbox 的
user-selected 文件权限 entitlement：`pickFiles` / `getDirectoryPath` 要求
read-only 或 read-write 任一，`saveFile` 只认 read-write。

而 `macos/Runner/DebugProfile.entitlements` 与 `Release.entitlements` 两者
**都没有** `com.apple.security.files.user-selected.*` 这两个 key。结果是全库
28 处 `FilePicker` 调用全部失败，用户实测到两个症状：

- 「笔记本 → 导入文档」点击后**无任何反应**
- 「文档语音朗读 → 导入文档」弹出 `PlatformException(ENTITLEMENT_NOT_FOUND), Either the Read-Only or Read-Write...`

两种表现的差异不在根因，而在调用方的错误处理：前者没有 try/catch，异常从
`onPressed` 逃逸后被静默吞掉；后者有 catch，所以可见。

这不是回归：`pubspec.lock` 在 HEAD 与当前同为 `file_picker 10.3.10`，
entitlement 文件末次改动 `5b2e9ce`（在本轮主题重构之前），该状态自
file_picker 升入 10.3.x 起即存在。

## What Changes

- **两个 entitlement 文件补齐 key**（`DebugProfile.entitlements` 与
  `Release.entitlements` 同步改）：
  - `com.apple.security.files.user-selected.read-only` = true
  - `com.apple.security.files.user-selected.read-write` = true
  - `read-write` 必须加：全库 **5 处** `saveFile`（导出 MP3、密码备份、
    思维导图导出、字幕保存、对比报告保存）走 `checkEntitlement(.requireWrite)`，
    只给 read-only 会让它们换成 `ENTITLEMENT_REQUIRED_WRITE` 继续失败。
- **`_importDocuments` 补 try/catch**：让 picker 失败以 SnackBar 可见地报出来，
  而不是点击无反应。
- **`main.dart` 六个窗口入口加全局异常兜底**（`runZonedGuarded` +
  `FlutterError.onError` + `PlatformDispatcher.instance.onError`）：
  任何未捕获的 async 异常至少要留下日志，不再静默。

**非目标：**
- 不启用 App Sandbox（`ENABLE_APP_SANDBOX` 保持关闭）。加 entitlement 只为
  满足 file_picker 的校验，不开沙盒；开了会牵动全库文件 I/O 的重审。
- 不为 28 处 FilePicker 调用逐一补错误处理——只修最关键的导入路径 + 全局兜底。
- 不改 file_picker 版本。

## Capabilities

### New Capabilities

- `macos-file-access-entitlements`: 定义 macOS 打包产物必须声明的文件访问权限，
  保证系统文件面板（选择/保存）在全部工具中可用，且失败时必须可见而非静默。

### Modified Capabilities

- `app-shell`: 补充「任何窗口的未捕获异常必须留下诊断信息」的约束，避免用户
  操作后无反应且无日志可查。
- `notebook-tool`: 补充「导入文档失败必须向用户报告」的约束。

## Impact

**代码 — 打包配置（2 个文件）：**

| 文件 | 改动 |
|---|---|
| `macos/Runner/DebugProfile.entitlements` | +2 key |
| `macos/Runner/Release.entitlements` | +2 key |

**代码 — 健壮性（2 个文件）：**

| 文件 | 改动 |
|---|---|
| `lib/tools/notebook/ui/notebook_page.dart` | `_importDocuments` 包 try/catch，失败弹 SnackBar |
| `lib/main.dart` | 六个窗口入口的 `runApp` 改为带全局错误兜底 |

**恢复的功能（全库 28 处调用）：**

```
pickFiles          11 处   doc_audio_reader / notebook×2 / password
                          slimmer / ops_tool / kma / bc_config / app_shortcut …
getDirectoryPath   12 处   各工具的目录选择
saveFile            5 处   doc_audio_reader:224 / password:75
                          notebook/mindmap:131 / ai_subtitles_dialog:366
                          folder_compare:305
```

**注意 `scripts/deploy_local.sh`**：其 `resign` 步骤是
`codesign -s - --force "$SOURCE_APP"`，**未传 `--entitlements`**。
需确认该调用不会剥掉 Xcode 已注入的 entitlement，否则部署版仍会失败
（这正是用户部署版遇障的可能路径之一）。若会剥掉，需改为显式传 entitlement 文件。

**不变更：**
- 任何业务逻辑、UI、数据层
- `pubspec.yaml` / `pubspec.lock`
