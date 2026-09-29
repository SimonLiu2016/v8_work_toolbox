## 1. 先证实「重签是否剥 entitlement」

> 这一步是 design 决策 3 的依据。若证实会剥，决策 3 从防御性升级为必需。

- [x] 1.1 对 `build/macos/Build/Products/Release/V8WorkToolbox.app` 跑
      `codesign -d --entitlements - <app>`，把输出存档
- [x] 1.2 手动执行 `codesign --remove-signature` + `codesign -s - --force`（模拟 deploy 脚本的 resign），再取一次 entitlements
- [x] 1.3 比对两次输出：确认 `files.user-selected.*` 是否在重签后消失
- [x] 1.4 把结论记入下方实施记录——若会剥，`deploy_local.sh` 必须显式传 `--entitlements`

## 2. 补 entitlement

- [x] 2.1 `macos/Runner/Release.entitlements` 加
      `com.apple.security.files.user-selected.read-only` = true
- [x] 2.2 `macos/Runner/Release.entitlements` 加
      `com.apple.security.files.user-selected.read-write` = true
- [x] 2.3 `macos/Runner/DebugProfile.entitlements` 同步加同样的两个 key
- [x] 2.4 新增测试：读两个 entitlements 文件，断言两个 key 都存在且两文件一致
- [x] 2.5 确认 `ENABLE_APP_SANDBOX` 仍为 NO（design Non-Goals：不开沙盒）

## 3. deploy 脚本显式传 entitlement

- [x] 3.1 `scripts/deploy_local.sh` 的 `resign` 步骤追加
      `--entitlements "$PROJECT_DIR/macos/Runner/Release.entitlements"`
- [x] 3.2 在脚本注释中说明为什么必须显式传（不带 `--entitlements` 时
      `--force` 不会保留原 bundle 的 entitlement）
- [x] 3.3 若 1.x 证实不会剥，仍保留显式传（让不变量写进源码，防未来回归）

## 4. picker 失败可见化

- [x] 4.1 `lib/tools/notebook/ui/notebook_page.dart` 的 `_importDocuments`
      包 try/catch，失败弹 SnackBar（参照 `doc_audio_reader_page._importLocalFile`
      的既有写法）
- [x] 4.2 确认报错文案包含原始异常信息，便于用户回报

## 5. 全局异常兜底

- [x] 5.1 `lib/main.dart` 提取一个共享的 `runAppWithErrorHandling(App)`，内含
      `runZonedGuarded` + `FlutterError.onError` + `PlatformDispatcher.instance.onError`
- [x] 5.2 六个入口（`V8WorkToolboxApp` / `_PasswordVaultWindowApp` /
      `_NotebookWindowApp` / `_SingleNoteWindowApp` / `_OpsToolWindowApp` /
      `LookupWindowApp`）全部改走该函数
- [x] 5.3 确认 `runZonedGuarded` 未改变平台通道行为（见 design 决策 4 的 Trade-off）

## 6. 验证与部署

- [x] 6.1 `flutter analyze` 0 error
- [x] 6.2 entitlements 一致性测试通过
- [x] 6.3 `flutter test` 全量，失败数不高于基线（`+677 ~1 -12`）
- [x] 6.4 `flutter build macos --release` 通过
- [x] 6.5 对**构建产物**（先别部署）跑 `codesign -d --entitlements -`，确认两个 key 已在产物里
- [x] 6.6 执行 `./scripts/deploy_local.sh`
- [x] 6.7 部署后再取一次 entitlements，确认两个 key 仍在（验证 3.1 有效）
- [x] 6.8 人工冒烟全库 28 处 FilePicker 调用，至少覆盖：
      notebook 导入文档、doc_audio 导入文档、doc_audio 导出 MP3、
      slimmer 选目录、password 备份保存、notebook 思维导图导出、
      ai_subtitles 保存、folder_compare 保存报告、ops excel 模板、kma 目录

## 实施记录

### §3 的实际结果超出原计划

3.3 原本写"若 1.x 证实不会剥，仍保留显式传"。实际结论相反：
**不传确实会剥**（§6.5 对照实验坐实），所以这条从"防御性"升级为"必需"，
`resign` 里还加了签后 `codesign -d --entitlements` 验收，缺 key 直接 die。

## 实施记录

### §1 结论：猜想方向对了一半，实际更根本

```
1. Xcode 构建产物   codesign -d --entitlements  →  空
                    Release.entitlements 里那 4 个 key 根本没进签名
2. 模拟 deploy resign 前后                        →  都是空
                    → 「重签剥 entitlement」不成立：本来就是空的，无从剥
3. 显式 --entitlements <file> 签                  →  成功注入 4 个 key ✓
```

影响：
- deploy 脚本显式传 `--entitlements` 这条**无论如何都要加**（结论 3 证明它有效）

### §6.5 对照实验：不传 --entitlements 确实会剥掉

```
不传 --entitlements 重签  →  签名 entitlement 为空（plutil 解析 NULL 失败）
传   --entitlements 重签  →  7 个 key 全在
```

→ `deploy_local.sh` 的显式传参**已证实为必需**，不是防御性优化。
→ "Xcode 直跑可能正常、部署版点不动"的差异正是这么来的。

### §6.5b 订正：Xcode 其实签得好好的

§1 那次查的是**加 key 之前的旧产物**，所以看到空。加了 key 重新构建后：

```
$ codesign -d --entitlements :- <产物>
{
  com.apple.security.automation.apple-events           => 1
  com.apple.security.cs.allow-unsigned-executable-memory => 1
  com.apple.security.files.user-selected.read-only      => 1   ✓
  com.apple.security.files.user-selected.read-write     => 1   ✓
  com.apple.security.get-task-allow                    => 1   ← 本地 ad-hoc 签名所致
  com.apple.security.network.client                    => 1
  com.apple.security.network.server                    => 1
}
```

→ §1 的推论「Xcode 没签进去」**不成立**，特此订正。
→ deploy 脚本那条**反而更关键**：Xcode 签好了，但 deploy 的
  `--remove-signature` + `--force` 重签会把它**剥掉**（§1 结论 2 实测），
  所以不显式传 `--entitlements` 的话部署版仍然坏。这正是"Xcode 直跑可能正常、
  部署版点不动"的真正原因。

### §4 一处命名冲突已解

外层变量取名 `picked`（`List<PlatformFile>`）与循环里原有的
`for (final picked in result.files)` 撞名。把循环变量改为 `file`，
循环体内 4 处 `picked.path/name` 一并改为 `file.path/name`。

### §5 需补两个 import

`runZonedGuarded` 来自 `dart:async`、`PlatformDispatcher` 来自 `dart:ui`——
`flutter/material.dart` 不导出它们，故在文件顶部显式加：

```dart
import 'dart:async' show runZonedGuarded;
import 'dart:ui' show PlatformDispatcher;
```

### §6 验证结果（截至部署）

```
analyze          0 error，220 issues（基线 216）
entitlements 测试 5 断言全过（含"删一个 key 就红"的实测）
flutter test     +650 ~1 -10；相对父基线（/tmp/base_fails.txt）**零新增失败**
release build    164.6MB
产物 entitlements  7 key 全在，含 files.user-selected.{read-only,read-write} ✓
部署 entitlements  同左，get-task-allow 消失（部署版更干净）✓
deploy AOT       1909aa98 → 8945d554
对照实验         不传 --entitlements 重签 → 签名 entitlement 为空（坐实因果）
```

**人工冒烟结论（用户已确认通过）**：28 处 FilePicker 调用点验证完成，
notebook 导入文档（原"无反应"）与 doc_audio 导入文档（原报错）均恢复正常，
saveFile 系列（导出 MP3 / 思维导图 / 密码备份 / 字幕 / 对比报告）亦可用。

（记录完毕）
