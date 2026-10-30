## Why

笔记本作为独立子窗口运行（`NotebookToolDefinition.openInNewWindow`），而 `main()` 的
notebook 分支在 `AiConfigStore.instance.init()` 之前就 `return` 了。该 init 是全仓库
唯一入口，于是子窗口进程里的槽位绑定表始终为空，「问我的笔记」必然报
`槽位 "text" 无可用候选供应商`——**同一时刻主窗口的调用全部成功**，供应商本身可用。

同时，上一轮界面打磨把资产面板改成弹窗后，弹窗持有的是打开时的 `Note` 快照，而
`NoteEditor._refreshMetadata()` 只重读笔记本/标签/关联三份列表，从不重读当前笔记，
导致保存后重开弹窗看到的仍是旧值，表现为「内容丢失」。

两个都是**子窗口进程模型下的状态失效**：前者是单例从未初始化，后者是快照从不刷新。

## What Changes

**1. 子窗口的 AI 配置初始化（ai-configuration）**

- notebook 子窗口分支补 `AiConfigStore.instance.init()`（其内部会带上
  `KeychainService.init`）与 `ProxySettings.instance.load()`，使槽位路由与密钥读取
  在子窗口内可用。
- 新增一条规格：**任何承载 AI 能力的窗口进程，必须在 `runApp` 前完成其依赖的
  平台级单例初始化**。以「服务清单」的形式固化，避免再漏。
- `AiConfigStore` 读取 `ai_config.json` 失败时不再静默 `_initDefaults()` 覆盖内存态，
  而是保留错误信号——否则配置损坏与「未初始化」在现象上不可区分。

**2. 资产弹窗的快照刷新（notebook-editor）**

- 资产弹窗保存后，`NoteEditor` 重新按 noteId 读取最新 `Note`，使 chip 文案（品类 /
  到期倒计时）与弹窗内的日期行显示真实值。
- 弹窗内的 `AssetFieldsPanel` 改为按 noteId 拉取最新 note，而非完全信任传入快照。

**3. 子窗口缺失 init 的显式化**

- 把 `main()` 各子窗口分支依赖的服务整理成一份清单并注释化，缺失时打印明确告警
  （而非等用户在功能层看到「槽位无候选」这类下游症状）。

## Capabilities

### New Capabilities

- `window-service-initialization`: 每个窗口进程（主窗口与各 `desktop_multi_window`
  子窗口）在 `runApp` 前必须完成其功能所依赖的平台级单例初始化；未初始化的服务
  不得表现为「功能静默失效」，而应有可诊断的信号。

### Modified Capabilities

- `ai-configuration`: 供应商与槽位绑定在**任何承载 AI 能力的窗口进程**中都必须
  可用，不仅限于主窗口；槽位不可用的报错必须能区分「未初始化」与「确实未绑定」。
- `notebook-editor`: 资产/凭证入口的显示值必须反映数据库现值，保存后立即刷新而非
  沿用打开时的快照。

## Impact

- **修改**：`lib/main.dart`（子窗口分支补初始化 + 服务清单注释）、
  `lib/services/ai_config_store.dart`（初始化失败保留错误信号）、
  `lib/tools/notebook/ui/note_editor.dart`（保存后重读 note）、
  `lib/tools/notebook/ui/asset_fields_panel.dart`（弹窗按 noteId 拉最新值）
- **无 schema 变更、无存储格式变更、无新增依赖**
- **风险**：子窗口多初始化几个单例会略微延长子窗口启动时间；`ProxySettings.load()`
  依赖 `SettingsStore`，故 notebook 分支需保证 `SettingsStore.init()` 在其之前
  （当前子窗口分支未初始化 `SettingsStore`，需一并补）
