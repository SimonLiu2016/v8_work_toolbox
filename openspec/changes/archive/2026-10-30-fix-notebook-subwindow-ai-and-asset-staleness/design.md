## Context

见 proposal.md「Why」。设计层需要知道的现状约束：

**进程模型**。`desktop_multi_window` 的子窗口是同一二进制重新拉起一个 Flutter engine
（`FlutterMultiWindowPlugin.swift:107` 只设 `dartEntrypointArguments`），因此 `main()`
会在每个子窗口进程里完整重跑一遍，`await Xxx.init()` 也是每进程各跑一次。单例状态
**进程级隔离**，不跨窗口共享。

**当前 `main()` 的形状**（`lib/main.dart`）：

```
main(args)
 ├─ isSubWindow == 'notebook'  → NoteStore.init() → runApp  ← 提前 return
 ├─ isSubWindow == 'password-vault' → runApp                 ← 提前 return
 ├─ isSubWindow.startsWith('note:')  → NoteStore.init() → runApp ← 提前 return
 └─ 主窗口：SettingsStore → ProxySettings → AiConfigStore → …
```

`AiConfigStore.instance.init()` 是全仓库唯一调用点（`grep` 确认），且位于 notebook
分支 return 之前不会被执行到。

**`AiConfigStore.init()` 的依赖链**：它内部调用
`KeychainService.instance.init(customRootDir: dir)`（同一目录），而密钥读取
（`readSecret`）是子窗口问答的必经路径。`ProxySettings.load()` 依赖
`SettingsStore`，当前 notebook 分支也未初始化 `SettingsStore`。

**`AiService` 的 HTTP client 构造时机**：`http.Client _client = AppHttpClient.create()`
是**字段初始化器**，在 `AiService.instance` 首次被触及时就执行，此时若
`ProxySettings` 未 load，`isConfigured` 为 false → 直连。所以代理必须在任何 AI 调用
之前 load，而非调用时。

**资产弹窗的数据流**（见 proposal）：`showAssetDialog(note: widget.note)` 传入快照，
`AssetFieldsPanel` 的 `initState`/`didUpdateWidget` 读 `widget.note`，而弹窗内的
`widget.note` 永不变化。父层 `NoteEditor._refreshMetadata()` 只调 `_loadMetadata()`
（重读 notebooks/tags/关联），不重读 note 自身。

**为什么测试没抓到**：`test/notebook_kb_service_test.dart` 只测检索与上下文构建，
没有任何测试以「子窗口进程」为前置条件驱动 `AiService.chat`；资产测试
（`test/notebook_asset_fields_test.dart`）只测 `NoteDatabase` 层，不测 UI 刷新链。

## Goals / Non-Goals

**Goals**
- 子窗口进程的 AI 能力与代理通道与主窗口一致，且这一致性由**显式清单**保证而非
  靠记忆。
- 资产入口的显示值来自持久化现状，保存后立即可见。
- 「未初始化」与「确实未绑定」在诊断上可区分。

**Non-Goals**
- 不改槽位路由算法、不改 `AiConfigStore` 的存储格式、不改密钥存储格式。
- 不把 `AiConfigStore` 改成跨进程共享（如共享内存/文件监听热重载）——那是另一个量级
  的工作，本次只需进程内一致。
- 不为每个子窗口补全主窗口的所有 init（只补该窗口功能实际依赖的），避免无谓拉长
  启动时间。
- 不改 `main()` 的子窗口分发机制本身（仍用 `desktop_multi_window`）。

## Decisions

### D1: 用显式「窗口 → 必需服务清单」替代在每个分支里散写 init

在 `main.dart` 引入一份按窗口类型声明的必需服务清单（数据 + 一个统一的
`_initServicesFor(windowKind)`），各分支改为声明式调用。

**为什么**：当前形态是「每个分支手写自己需要的 init」，漏一个就是本次这类静默失效。
把清单变成代码里唯一一处显式结构后，(a) 遗漏在 review 时可见，(b) 新增平台级单例时
有明确的地方要改，(c) 可以写测试断言「清单覆盖了该窗口实际使用的服务」。

**被否**：在每个子窗口分支各补几行 `await`（本次就是这样漏的，会再漏）；把子窗口
改成复用主窗口的 isolate（`desktop_multi_window` 不支持，等于换框架）。

### D2: notebook 子窗口必需服务 = SettingsStore + ProxySettings + AiConfigStore + NoteStore

`AiConfigStore.init()` 自带 `KeychainService.init()`，不单独列。

**为什么**：这四项覆盖笔记本子窗口的全部 AI 路径——配置与槽位（AiConfigStore）、
密钥（KeychainService，内部）、代理通道（ProxySettings，且必须在 `AiService` 首次
 touch 之前 load，见 Context）。

**顺序约束**：`ProxySettings.load()` 依赖 `SettingsStore`，故 SettingsStore 必须在前。
清单按拓扑序声明并串行执行。

**被否**：只补 `AiConfigStore`（代理场景下子窗口仍会绕过代理直连，超时现象会被
误判为供应商故障——这正是历史上排查过的坑）。

### D3: 初始化失败显式化——记录并可诊断，不让下游表现为「配置为空」

`AiConfigStore.init()` 当前 `catch (e) { debugPrint(...) }` 后继续，`_load()` 内部又
会 `_initDefaults()` 把内存态覆盖成空。改为：保留一个 `lastInitError` 字段 + 一个
`isInitialized` 标志；`chat()` 在候选为空时，若 `isInitialized == false` 或有
`lastInitError`，抛出的 `SlotUnavailableException` 携带该原因，消息明确区分
「本进程配置未初始化」与「该槽位确实没有绑定候选」。

**为什么**：现象可归因是这次排查最大的成本（三个错误时间戳夹在主窗口成功调用之间
才推断出进程差异）。规格已要求区分，见 specs。

**被否**：初始化失败就 `throw` 阻断 `runApp`（违反 main() 的 fail-soft 契约，
会让整个子窗口黑屏——`flutter-macos-deploy-pitfalls` 记忆里的红线）；只加日志不
改错误消息（用户仍看到「无可用候选供应商」，归因成本不变）。

### D4: 资产弹窗改为按 noteId 拉取最新 note，保存后强制父层重读

两处改动：
1. `AssetFieldsPanel` 打开时按 noteId 读一次最新 `Note`（`NoteStore.instance.noteById`），
   而非完全信任传入快照；传入快照仅作为首帧占位。
2. `NoteEditor._refreshMetadata()` 增加「重读当前 note」——重新 `noteById` 并用最新
   实例重建自身状态，使元数据栏 chip 与后续弹窗都拿到新值。

**为什么**：单一数据源是数据库，UI 只是投影。快照只在「打开瞬间」合理，跨保存必然
过期。父层重读是必要的——chip 文案（品类/到期倒计时）来自 `widget.note`，不重读则
chip 仍旧。

**被否**：只在 `AssetFieldsPanel` 内部 `setState` 更新（chip 在父层，仍显示旧值）；
用全局事件总线广播 note 变更（引入新机制，收益仅此一处）；让 `NoteEditor` 订阅
drift 的 note 表更新流（改动面最大，且 `NoteStore` 当前未暴露 watch，超出本次范围）。

### D5: 不为资产刷新引入持久化缓存层

不新增任何 note 缓存。

**为什么**：`NoteStore.noteById` 已是直查 SQLite，无缓存层可改；问题从来不是读得慢，
是没人去读。

## Risks / Trade-offs

**[子窗口启动时间变长]** → notebook 分支多 init 三个单例，其中 `AiConfigStore.init()`
读一个 1.9KB JSON、`KeychainService.init()` 读 DEK。缓解：串行但都是本地小文件 IO，
毫秒级；且这些初始化在主窗口本就发生，成本已知。

**[`SettingsStore` 在子窗口首次 init 的副作用]** → 它可能触发配置迁移或写盘。
缓解：`readToolConfig` 已有 `if (_configDir == null) await init()` 的自愈路径，
说明子窗口路径本就预期它会懒初始化；显式 init 只是把时机提前到 runApp 前。

**[D3 改动 `SlotUnavailableException` 消息]** → 现有测试可能断言旧消息文本。
缓解：任务里包含跑全量 `flutter test` 并对受影响断言做修正（只改文本断言，不改语义）。

**[D4 父层重读 note 触发额外重建]** → `_refreshMetadata` 每次弹窗关闭都重读一次
note + setState。缓解：note 是单行查询，且仅在弹窗关闭这一低频动作发生；不影响编辑
过程中的事务流。

**[仍有其他子窗口未覆盖]** → `password-vault` 与 `note:<id>` 分支同样可能缺服务。
缓解：本次不扩大范围（它们当前不消费 AI），但 D1 的清单结构使后续补充是一行声明；
在 design 记明这是已知的待补项而非遗漏。

## Migration Plan

1. **D1+D2**：重构 `main.dart` 为清单驱动，notebook 分支声明其必需服务。此步即可
   修复「问我的笔记」的槽位报错。
2. **D3**：`AiConfigStore` 增加初始化状态与错误承载，`SlotUnavailableException`
   消息区分两种成因。
3. **D4**：资产弹窗按 noteId 拉最新 + 父层保存后重读 note。
4. **测试与部署**：新增/修正测试，`flutter clean` → release 构建 → `codesign -v --strict`
   → 安装 → AOT 快照哈希校验 → 启动采样。

**回滚**：三组可独立回滚。D1 回滚即恢复手写 init；D3 回滚即恢复旧消息；D4 回滚即
恢复快照直传。无声明的数据迁移。

## Open Questions

无。两个根因都已在代码层确证（`AiConfigStore.init` 唯一调用点在 notebook 分支
return 之前；`_refreshMetadata` 不重读 note），方案不依赖未验证假设。

一个待实机确认项记入 tasks：用户此前填写的资产数据是否真的落库（应用已关，当前库
中资产列全为空，无法复现当时写入结果）。这不影响修复方案——D4 同时覆盖「写了不显示」
与「没写」两条路径的可诊断性。
