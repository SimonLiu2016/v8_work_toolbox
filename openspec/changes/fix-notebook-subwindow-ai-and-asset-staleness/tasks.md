# Tasks: 修复笔记本子窗口 AI 失效与资产快照过期

> 两组独立修复 + 显式化改造，按依赖排序：先修子窗口初始化（组 1，直接消除当前
> bug），再做诊断可归因（组 2），最后资产快照（组 3，独立文件链）。

## 1. 子窗口必需服务清单化（修复「问我的笔记」）

- [x] 1.1 在 `lib/main.dart` 引入按窗口类型声明的必需服务清单（数据 + 统一的初始化函数），替换各子窗口分支散写的 `await Xxx.init()`；清单内服务按拓扑序串行执行（design D1）
- [x] 1.2 notebook 子窗口声明其必需服务：`SettingsStore` → `ProxySettings` → `AiConfigStore`（自带 `KeychainService`）→ `NoteStore`（design D2）
- [x] 1.3 复核 `password-vault` 与 `note:<id>` 两个分支：确认其当前不消费 AI，按实际依赖声明清单（缺则补，不缺则显式写空并在注释说明「已知待补项」）
- [x] 1.4 单文件 init 失败时不阻断 `runApp`，但记录明确的错误信号（debugPrint + 可选的状态字段），符合 main() 的 fail-soft 契约
- [x] 1.5 新增测试：以 notebook 子窗口等价路径驱动 `AiService.chat(slot: 'text')`，断言能解析到 `ai_config.json` 中的候选（先在临时目录写好配置再 init，验证「子窗口进程不再报槽位无候选」）

## 2. 初始化状态可诊断（区分「未初始化」与「未绑定」）

- [x] 2.1 `AiConfigStore` 增加 `isInitialized` 与 `lastInitError`；`init()` 失败时记录原因而非静默继续
- [x] 2.2 `SlotUnavailableException` 携带「本进程配置未初始化/加载失败」的原因；消息与「该槽位确实没有绑定候选」明确区分（specs: ai-configuration）
- [x] 2.3 `AiService.chat` 在候选为空的分支读取上述状态并填入异常，使用户看到的报错可归因
- [x] 2.4 修正受影响的既有测试断言（若断言旧消息文本），不改语义
- [x] 2.5 新增测试：构造「配置损坏」与「槽位为空但配置正常」两种情形，断言两者抛出的错误消息不同且都能指明成因

## 3. 资产弹窗快照刷新

- [x] 3.1 `AssetFieldsPanel` 打开时按 noteId 读取最新 `Note`（`NoteStore.instance.noteById`），传入快照仅作首帧占位；读取失败时回落到快照并记录
- [x] 3.2 `NoteEditor._refreshMetadata()` 增加「重读当前 note」：重新 `noteById` 后用最新实例更新自身状态，使元数据栏资产 chip（品类 / 到期倒计时）与关联计数反映真实值
- [x] 3.3 弹窗保存后父层刷新链路验证：`showAssetDialog` 返回 → `_refreshMetadata` → chip 文案变化（specs: notebook-editor）
- [x] 3.4 新增测试：连续两次保存不同资产字段，断言第二次保存基于第一次的结果（不清空、不回退）；以及「外部改动后重开弹窗读到新值」

## 4. 验证与收尾

- [x] 4.1 全量回归 `flutter test`，确认无新增失败（既有失败清单需与改动前一致）
- [x] 4.2 构建部署：`flutter clean` → `flutter build macos --release` → `codesign -v --strict` 通过 → 安装（经 `/tmp/deploy` 暂存，不用 `cp -R` 直接覆盖）→ 校验 AOT 快照哈希 → 启动采样 stderr 无未捕获异常
- [ ] 4.3 实机验证：打开笔记本独立窗口 → 「问我的笔记」提问能拿到基于笔记的回答（不再报槽位无候选）；配了代理时子窗口请求走代理
- [ ] 4.4 实机验证：资产弹窗填写品类与日期 → 完成 → 重开弹窗内容仍在，元数据栏 chip 显示对应文案
- [ ] 4.5 实机确认遗留项：此前填写的资产数据是否曾落库（当前库中资产列全空，无法复现当时结果）
