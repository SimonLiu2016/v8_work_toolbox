## 1. 桥：返回分组释义与例句（不动扁平字段）

- [x] 1.1 ✅ `/dictionary` 响应体新增 `meanings`（`partOfSpeech`/`definitions`/`examples` 三字段），从 `result.meanings` 原样映射。`definitions` 扁平数组逐字未动
- [x] 1.2 ✅ `matched == false` 时 `meanings` 是 `const <Map<String,dynamic>>[]`，与 `definitions` 的空态一致
- [x] 1.3 ✅ 注释写明两形状并存的理由（flat 是既有契约 / 分组给要渲染的客户端），并显式说明**没有 `phrases` 字段且不是遗漏**（有道响应无短语分区 + spec 的 deliberate absence scenario），免得后来者当漏字段补
- [x] 1.4 ✅ 新增 3 例（共 21 例全过）：`meanings` 三字段原样过去含空 `partOfSpeech` 也成组；**flat 与分组展开内容相等**（核心不变量）；例句随分组过去、无例句组是 `[]` 而非 null。既有 `definitions` 断言全部保留 = 向后兼容的证据
- [x] 1.5 ✅ 未收录时 `meanings` 为空数组（断言补在既有的 no-match 用例里，避免重复造一个请求）

## 2. 扩展：透传 + 分组渲染

- [x] 2.1 ✅ `handleFetchDictionary` 透传 `payload.meanings`（非数组则为 null，让气泡据此回落）；`matched !== true` 的早退分支返回 `meanings: []`。字段名与桥一致
- [x] 2.2 ✅ `fetchDictionary` 的 `onResolved` 回调把整份 `data`（含 `meanings` 与每组 examples）存进 `resolvedData`，渲染与加生词本共用同一份
- [x] 2.3 ✅ 拆出 `renderGrouped(meanings)` 与 `renderFlat(definitions)`：有 `meanings` 走分组（词性标签独立一行 + 该组释义 + 该组例句），否则走**原封不动**的老扁平路径。词性不再充当释义串的前缀
- [x] 2.4 ✅ 例句每至多 2 条（`slice(0, 2)`），沿用卡片既有 `max-height: 220px` 滚动；例句区块只在 `exs.length` 非零时渲染，无例句不产生占位
- [x] 2.5 ✅ 新增的词性/释义/例句全部过 `escapeHtml`。它是模板字符串拼接而非 DOM API，`escapeHtml` 同时加固为 `String(str)`（null 不再炸）；只替换 `& < > "` 对词典文本够用，未引入新依赖
- [x] 2.6 ✅ `addToVocab` 消息体新增 `examples: collectExamples(resolvedData)`。`background.js` 与桥侧本就在收这条字段，桌面浮窗那条路本来就写例句——只有气泡这条漏了，补齐

## 3. 验证

- [x] 3.1 ✅ 全量 `flutter test`：1343→**1347 passed** / 3 skipped / 20 failed，**失败集合与基线逐字相同、零新增**。
  - 唯一多出来的一条计数（-21）是 `legacy_importer_test.dart` 在**加载阶段**[E]（`loading ... [E]`），而 baseline 日志里这个文件一次都没出现——两次跑的加载顺序不同。单独重跑它：+10 All tests passed。判定为加载期 flaky，非本次回归。
  - `flutter analyze lib/`：**0 error**（163 个 info/warning 全部是既存的，分布在 slimmer / doc_audio 等未触碰文件）
- [x] 3.2 ✅ `./scripts/deploy_local.sh` 完整跑通：clean → release build → 注入 mihomo (f4b5fd41) → ad-hoc 重签 → 替换 → 启动，`DEPLOY_EXIT=0`。四关卡全过：`codesign -v --strict` 通过、entitlements 双 key 在签名内、AOT 快照 `428d5c6a…` → `ae175c5f…`、新实例 PID 44971 存活
- [x] 3.3 ⚠️ **脚本只能提醒，不能代劳**——扩展 reload 是用户在 `chrome://extensions` 点的按钮。此项未完成前不要验 3.4-3.7：未打包扩展不自动重载，跑的还是旧 content.js，症状是「部署了但气泡没变」且无任何报错。已向用户明确告知
- [x] 3.4 ✅ 用户实机确认（2026-10-08）：选中多词性单词 → 气泡按 `adj.` / `n.` 分组，各自带释义，例句可见
- [x] 3.5 ✅ 用户实机确认：无例句的词不产生空的例句区块（不留占位）
- [x] 3.6 ✅ 用户实机确认：短语（如 `look forward to`）释义正常显示；词性标签缺失符合预期——有道对短语不给 `adj.` 式前缀，这是数据源属性而非缺陷，spec 已记录
- [x] 3.7 ✅ 用户实机确认：「加生词本」后详情页词条带例句（桌面浮窗那条路本来就有，气泡这条本次补齐）
- [x] 3.8 ✅ 用户实机确认：回落路径成立——新扩展 + 旧桥时气泡仍是原有扁平渲染，不白屏不报错。这条在本次部署前已天然验证过（当时 app 旧、扩展已 reload）
