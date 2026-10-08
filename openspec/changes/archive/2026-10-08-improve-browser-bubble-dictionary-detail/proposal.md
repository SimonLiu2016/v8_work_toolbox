## Why

浏览器选中单词后弹出的原位气泡里，**只能看到中文解释**。用户明确说"词性、常用短语等都没有，这些都是很重要的信息"。

根因不在气泡的渲染，而在桥这一层的数据契约：`local_dictionary_bridge.dart` 的 `/dictionary` 端点只返回 `result.allDefinitions`——`DictionaryResult.meanings` 被拍平成字符串列表，`partOfSpeech` 只剩释义串的前缀，`examples` 整个被丢掉。气泡端（`content.js`）只能用正则把词性从串首切出来做成小 chip，例句想要也没有数据。桌面浮窗和「存为笔记」用的都是分组结构，只有气泡这一路从一开始选了最省事的形状。

用户提到的"常用短语"是另一类问题：**有道这个免费响应里根本不存在短语字段**（整个 payload 扫过，`phrase`/`phrs`/`collocation` 零命中），`VocabEntryModel.phrases` 有列但全项目无人填充。它不是"被丢弃"，是"从无数据源"。因此本次**不改协议之外的行为**：气泡本次拿到它本来就有、却拿不到的数据；常用短语的数据源决策留给后续（见 Open Questions，不改 spec 不硬做）。

## What Changes

- **`/dictionary` 返回分组释义**：新增 `meanings` 字段（`[{partOfSpeech, definitions, examples}]`），与桌面 `DictionaryResult.meanings` 同构。**`definitions` 扁平数组保留**——它是既有契约，桌面端和扩展都在用，删除是 breaking；新增字段是纯增量，老扩展不读新字段，行为不变。
- **气泡按词性分组渲染**：`content.js` 改为优先读 `meanings`：词性 chip + 该词性下的释义列表 + 例句。拿不到 `meanings` 时（桥未升级 / 旧桌面端）回落现有扁平 `definitions` + 正则切词性的路径——**回落不是摆设，是兼容期的实际路径**。
- **气泡展示例句**（`examples` 非空时）：折叠或限量展示。气泡宽度 340px、`max-height: 220px`，塞满词性+释义+例句会溢出，所以按限量 + 可展开处理；具体形态属实现细节，spec 只要求"例句可得且可见"。
- **加生词本时带上例句**：扩展 `addToVocab` 消息已有 `examples` 参数（`background.js` 一直在收），但 `content.js` 的调用点没传——气泡解析结果里也没有。这次一并接上，让「加生词本」的词条带例句（桌面浮窗那条路本来就有）。
- **修掉 phrase 查询时词性解析的脆弱点**：`LookupCoordinator` 对 ≤3 词短语也走词典路（`look forward to` 会命中 ec），而有道对短语返回的释义串不以 `adj.` 开头，正则切不出词性，`partOfSpeech` 只能是空串。气泡用 `meanings[].partOfSpeech` 后，**单词至少能正确分组**；短语仍是空词性组（数据源限制），但不会再把"期待：指对未来…"误当成释义正文显示——这与桌面端现有行为对齐。
- **无协议变更**：深链、`/vocab` schema、密钥、CORS 均不动。

## Capabilities

### New Capabilities

（无）

### Modified Capabilities

- `local-dictionary-bridge`: `/dictionary` 端点返回分组释义与例句——spec 现有 scenario 明确说"returns structured dictionary data (word, phonetic, definitions, audio URL) equivalent to what the desktop application's own lookup panel would render"，而气泡实际拿到的是拍平子集，两者不一致。这次让契约与那句话对齐，并把例句纳入。
- `in-page-browser-bubble`: 气泡展示词性分组 + 例句；spec 现有 scenario 已声称"displays … Chinese definitions, and part-of-speech chips"，但例句从未在气泡里出现过，且"常用短语"无数据源一事需要显式记录（否则后来者会当作 bug 再查一遍）。

## Impact

- **Dart**：`lib/services/local_dictionary_bridge.dart`（`/dictionary` 响应体加 `meanings`；`/vocab` 补 `phrases` 占位说明而非新字段）。
- **JS**：`extensions/v8-browser-companion/content.js`（读 `meanings` 分组渲染 + 例句 + 回落）、`background.js`（`fetchDictionary` 透传 `meanings`；`addToVocab` 带上 `examples`）。
- **测试**：`test/local_dictionary_bridge_test.dart` 加 `meanings` 断言（既有 `definitions` 断言保留，证明向后兼容）；纯 JS 侧无单测框架，走实机验证。
- **数据/迁移**：无 schema 变更、无迁移。`VocabEntryModel.phrases` 仍然没人填——本次明确不改这个现状，只在 spec 记一笔。
- **依赖**：无新增。
- **回归风险**：仅新增字段 + 前端渲染偏好分组，扁平路径保留；`fetchDictionary` 对 `matched:false` 的处理不变。
