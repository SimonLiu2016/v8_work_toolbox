## Context

`file_picker` 10.3.x 的 macOS 端在 Swift 侧强制 entitlement 校验
（`FilePickerPlugin.swift`）：

```swift
pickFiles / getDirectoryPath  → checkEntitlement(.readOrWrite)   // 二者任一
saveFile                      → checkEntitlement(.requireWrite)  // 仅 read-write
```

`macos/Runner/{DebugProfile,Release}.entitlements` 都没有
`files.user-selected.*`，于是 28 处调用全失败。

已确认非回归：`pubspec.lock` 的 `file_picker` 在 HEAD 与当前同为 `10.3.10`；
entitlement 文件末次改动 `5b2e9ce`，早于本轮主题重构。

动机见 `proposal.md` — Why；契约见 `specs/macos-file-access-entitlements/spec.md`。

## Goals / Non-Goals

**Goals:**
- 28 处调用恢复可用。
- picker 失败必须可见。
- 未捕获的 async 异常留痕。

**Non-Goals:**
- 不开 App Sandbox（`ENABLE_APP_SANDBOX` 保持 NO）。加 entitlement 只是为了
  让 file_picker 的校验通过；一旦开沙盒，全库文件 I/O 都要重新审（`AppPaths`
  root、mihomo 资源、加密备份……），那是独立的大工程。
- 不为 28 处调用逐个加错误处理。
- 不改 file_picker 版本、不替换成 file_selector。

## Decisions

### 1. 两个 entitlement 都加，不只 read-only

- **Decision**：`read-only` 与 `read-write` 都设为 true。
- **Rationale**：实测的 Swift 源码——`saveFile` 走
  `checkEntitlement(.requireWrite)`，只给 read-only 会让 5 处导出
  （MP3 / 思维导图 / 密码备份 / 字幕 / 对比报告）换成
  `ENTITLEMENT_REQUIRED_WRITE` 继续失败。
- **Alternatives Considered**：只加 read-only。权限面更窄、更"正确"，
  但会让 5 个既有功能继续挂。本机工具不过 App Store 审查，取可用性优先。

### 2. 两个 entitlement 文件同步改，且用脚本校验一致

- **Decision**：改 `DebugProfile.entitlements` 与 `Release.entitlements`；
  后续可用一个测试断言两者都含这两个 key，防止只改一个。
- **Rationale**：spec 的「Debug and release configurations agree」场景。
  历史上这两个文件内容一致，改漏一个的代价是"debug 好用、release 挂"
  或反过来——极难定位。

### 3. `deploy_local.sh` 的重签必须显式传 entitlement

- **Decision**：`codesign -s - --force "$SOURCE_APP"` 之后追加
  `--entitlements macos/Runner/Release.entitlements`。
- **Rationale**：`codesign --force` 不带 `--entitlements` 时，会用可执行文件
  `__TEXT` 段内嵌的 entitlement；而本项目实测该 binary 内**没有**
  user-selected 串。因此重签很可能把 entitlement 剥掉——这解释了为什么
  Xcode 直接跑可能正常、而部署版点不动（待任务 1.x 验证）。
  显式传文件可消除这一不确定性。
- **Trade-off**：传错文件路径会让 `codesign` 直接失败（fail-fast），比静默剥掉好。

### 4. 全局兜底用 `runZonedGuarded` + `FlutterError.onError`

- **Decision**：六个窗口入口的 `runApp(...)` 包进
  `runZonedGuarded(body, onError)`，并在其中设
  `FlutterError.onError` 与 `PlatformDispatcher.instance.onError`。
- **Rationale**：notebook 的"点击无反应"正是 `onPressed: _importDocuments`
  （async void）抛出的异常无人接。即便修了 entitlement，这类静默失败模式
  仍在——任何未来的 picker / I/O 错误都会同样消失。
  兜底至少让它进日志。
- **Alternatives Considered**：只给 `_importDocuments` 加 try/catch。
  不够——它只治一个调用点，而静默吞异常的调用方还有 27 处。
  两者都做：定点修 + 全局兜底。
- **Trade-off**：`runZonedGuarded` 会改变 Zone 上下文，需确认 Flutter 插件
  的平台通道与异步回调在此 Zone 下行为不变（六个入口都是简单 `runApp`，
  包裹层不引入新的异步边界，风险低）。

### 5. 不为 28 处调用逐个包 try/catch

- **Decision**：只给 `_importDocuments`（用户报障的那条）与导入/导出主路径加；
  其余靠全局兜底。
- **Rationale**：entitlement 修好后这些调用不再抛。逐个包 try/catch
  会 diff 巨大且大部分是死代码路径，违背本次"修根因 + 止血"的边界。

## Risks / Trade-offs

- **[Risk] 重签剥 entitlement 的猜想未被证实**：
  → *Mitigation*：设为任务 1.x 的第一步——用
    `codesign -d --entitlements -` 在重签前后各取一次，比对差异。
    若证实会剥，则决策 3 从"防御性"升级为"必需"；若不剥，仍保留显式传文件
    （更稳，且让不变量写进源码）。

- **[Risk] `runZonedGuarded` 影响既有异步行为**：
  → *Mitigation*：全量 `flutter test` 对比基线，六个入口各跑一次冒烟
    （主窗口、密码、笔记本、单笔记、磐石运维、查词）。

- **[Risk] 开了 entitlement 但没开 sandbox，会不会有副作用**：
  → *Mitigation*：entitlement 在非沙盒应用上只是"声明"，不影响文件访问行为；
    file_picker 的校验会因此通过。风险主要在将来若开沙盒，需要重新审
    已声明的权限是否够——已在 Non-Goals 中留痕。

- **[Trade-off] 用户可能报障的范围比 2 处大**：
  → *Mitigation*：proposal 的 Impact 表列出全部 28 处，验收时逐个冒烟一遍，
  而不是只验用户提的两个。

## Migration Plan

1. 先测重签是否剥 entitlement（决策 3 的依据）。
2. 两个 entitlement 文件加 key。
3. `_importDocuments` 加 try/catch + SnackBar。
4. 六个入口加全局兜底。
5. 加 entitlements 一致性测试（读两个 plist，断言 key 齐备）。
6. 全量验证 + 构建 + 部署 + 28 处逐个冒烟。
7. 回滚策略：entitlement 是加法、健壮性是包裹层，任一出问题可分别 revert。

## Open Questions

（无。根因已定位到具体 Swift 源码行，修法无取舍空间。）
