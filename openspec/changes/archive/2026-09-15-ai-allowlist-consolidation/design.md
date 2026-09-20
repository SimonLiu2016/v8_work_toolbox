## Context

白名单当前状态（动机见 proposal.md）：

- **匹配双端**：Dart 侧 `UnattendedService.isCommandInAllowlist`（`lib/services/unattended_service.dart:500`）与注入 hook 的 JS 侧 `evaluateSafety`（同文件 `:1431`）语义一致——每条规则先按正则（`multiLine`、忽略大小写）匹配，再退化为精确字符串相等。本变更只改规则**数据**，两端匹配逻辑不动，整理结果自动双端生效。
- **入口两处**：审计流水「加入白名单」按钮（`lib/tools/unattended/unattended_page.dart:954-979`）调用 `addToAllowlist`（`:516`，转义 + `^...$` 锚定）；规则管理弹窗 `_showAllowlistRulesDialog`（`:697`）的 actions 当前只有「清空白名单」「保存修改」。
- **AI 基建现成**：`AiService.instance.chat(slot: 'text', messages: ...)` 带自动愈合路由与 `SlotUnavailableException`，调用与降级文案范式参照 `lib/tools/slimmer/ai_disk_diagnostics_service.dart:189,223`。
- **安全约束**：白名单优先级**高于**黑名单（`evaluateSafety` 第 0 步）。AI 宽规则若过度泛化会架空机械安全硬地板，这是本设计最主要的威胁模型。

## Goals / Non-Goals

**Goals:**

- 白名单规则从"逐字符精确"演进为"语义通用"，同类命令一次覆盖。
- 存量（AI整理按钮）与增量（加入白名单智能合并）双路径，共用同一套簇检测、AI 合并与校验闸门。
- 所有合并结果生效前必经三重校验 + 用户确认；一切失败路径向"不泛化"降级。
- AI 不可用时功能体面降级：A 路径退化为本地预整理，B 路径静默退回精确规则。

**Non-Goals:**

- 不改变白名单匹配语义本身（正则 + 精确兜底的求值顺序、双端一致性）。
- 不引入规则优先级、分组管理、规则启用/禁用等通用规则引擎能力。
- 不做 AI 调用节流/配额管理（降级路径安全，属过度设计）。
- 不改动黑名单（denylist）的维护方式；仅消费其样本做交叉校验。
- AI 整理不自动保存——最终落库动作始终是用户的「保存修改」或确认对话框。

## Decisions

### D1: "明显相似"用字面锚点做机械可算的簇检测，而非交给 AI 判断

从规则文本中提取**字面锚点**：先对正则做反转义（`\.` → `.`、`\ ` → ` ` 等），再用路径正则（`/(?:[^\s/\\]|\\.)+(?:/(?:[^\s/\\]|\\.)+)*`）抽取所有绝对路径字面量，加上命令首个动词（`rm`/`mv`/`cp`/`git` 等首个 token）。两条规则 **anchors 交集非空 且 首个动词相同** → 同簇。

**为什么**：用户贴的三条 deploy 规则尾部（echo 文案、cut 位数、shasum 目标）全不同，但锚点 `{rm, /Applications/V8WorkToolbox.app}` 完全一致 → 同簇；而 `rm -rf /Applications/OtherApp.app` 锚点不交集 → 不碰。判定保守、可解释、可单元测试，且不消耗 AI 配额。

**备选**：让 AI 自由判断相似性 → 拒绝，聚类本身的可靠性不能用不可复现的模型判断做地基；编辑距离/AST 相似度 → 拒绝，shell 命令结构太松散，字面锚点已足够表达"同一操作对象"。

### D2: 三重校验闸门为纯函数，A/B 共用，fail-safe 方向为"不泛化"

`validateMergedRule(newRule, originalCommands, denylistSamples) → bool`：

1. **语法**：`RegExp(newRule)` 编译通过（Dart 侧编译即可——两端正则语义在此用途上一致，JS 侧非法规则本就被 catch 吞掉，Dart 校验已能挡住实质风险）。
2. **回验**：被合并的每条原始命令/规则**还原出的代表命令**必须被 `RegExp(newRule, caseSensitive: false)` 命中。注意对旧规则（已是正则）回验时，用它自身锚定前转义还原的字面命令作为测试样本。
3. **黑名单交叉**：`denylistSamples`（从 `UnattendedState.defaultDenylist` 每条模式派生一条代表性危险命令字符串，静态维护在代码中）全部不得命中。

任一失败 → 丢弃该簇合并，保留原规则。校验闸门放 service 层纯函数，直接喂单元测试（现有 `test/unattended_service_test.dart` 同构扩展）。

**为什么**：白名单优先级高于黑名单，校验闸门是防止"AI 整理把安全地板架空"的唯一结构性防线。回验的不变量（"整理后能放行的 ⊇ 整理前能放行的"）自包含，不需要用户参与即可机械验证。

### D3: AI 产出结构化 JSON（分组 + coversRules），而非直接改写文本

Prompt 要求 AI 严格返回：

```json
{
  "groups": [
    { "summary": "部署替换 V8WorkToolbox.app",
      "mergedRule": "^rm -rf /Applications/V8WorkToolbox\\.app && (mv|cp -a) \\S+V8WorkToolbox\\.app /Applications/",
      "covers": [0, 1, 2] }
  ],
  "untouched": [3]
}
```

**为什么**：`covers` 索引让 D2 的回验变成机械映射；UI 可展示"3 条 → 1 条"的对照预览；`untouched` 保证 AI 只动它敢动的。解析沿用 slimmer 的 `_parseJsonObject` 容错提取模式（剥离 markdown 围栏后取首个 JSON 对象）。

**泛化定调写进 system prompt**：泛化动词/来源路径/校验尾部，**目标路径保持字面**（如 `/Applications/V8WorkToolbox\.app` 永远字面化，来源 `mv /tmp/deploy/...` 可泛化为 `\S+`）；禁止 `.*` 直接覆盖路径段；输出必须是合法 Dart/JS 正则。

### D4: A 路径终点是"回填文本框"，B 路径终点是确认对话框——AI 永不直写状态

- **A（AI整理按钮）**：点击 → 本地预整理（去重 + 最长公共前缀合并）→ 簇检测 → AI 合并 → 校验 → **预览对话框**（逐组对照：旧规则列表 ↔ 新宽规则，附 AI summary）→ 用户确认 → 仅替换 `TextEditingController` 内容。白名单状态在用户点「保存修改」前不变。按钮处理中置 loading 并禁用，防重复点击。
- **B（加入白名单）**：`addToAllowlist` 流程前置两步：① 已被覆盖 → SnackBar 提示命中规则，返回；② 同簇检测命中且 AI 可用 → 校验过的合并方案弹确认对话框（[合并为宽规则] / [只加精确规则]）。AI 不可用/失败/校验不过 → 走现状精确路径 + 不阻塞 SnackBar。

**为什么**：白名单是无人值守下唯一的人工防线，任何一条规则生效都必须经过一次人类眼球；而 B 发生在高频批量处理流水的场景，确认对话框只在"AI 真的提出合并"时出现，不打扰常态路径。

### D5: 本地预整理独立于 AI，是 A 路径的无条件第一步

去重（trim 后字符串相同）+ 相同前缀合并（一规则是另一规则的前缀时保留更通用者）。**为什么**：这部分不需要 AI 就能消除最粗的冗余，AI 不可用时 A 路径仍有价值；也让 AI prompt 里的规则集更小，降低 token 与误判面。

### D6: 新增 `AllowlistConsolidationService`，不动 `UnattendedService` 的求值路径

簇检测、本地预整理、AI prompt 构建、JSON 解析、校验闸门收敛到新服务（`lib/services/allowlist_consolidation_service.dart`），`UnattendedService` 只新增薄入口（`suggestMergeFor(command)`、`applyConsolidation(...)` 等）供 UI 调用。**为什么**：求值路径（双端匹配）是安全敏感热路径，一行不动；新逻辑独立成服务便于单测与将来复用。

## Risks / Trade-offs

- [AI 产出看似合理但语义过宽的规则（如把多条 deploy 合并成 `^rm -rf /Applications/.*`）] → 黑名单交叉校验（D2-③）在确认前拦截；prompt 定调"目标路径字面化"（D3）；用户确认对话框兜底。
- [AI 返回非 JSON 或截断 JSON 导致解析失败] → 沿用 slimmer 的容错提取；解析失败按"AI 失败"路径静默降级（A：本地预整理结果仍回填；B：精确规则）。
- [宽规则被加入后，用户难以察觉其放行面变大] → B 路径确认对话框逐条列出将被替换的旧规则；A 路径预览对照展示。审计流水 `matched_whitelist: <pattern>` 日志天然记录命中规则，可追溯。
- [簇检测误并（两条命令碰巧同动词同路径但语义不同，如 `cat /app/log` vs `rm /app/log`）] → 首个动词必须相同已排除此类；残留风险由回验（旧命令必须仍命中——宽规则只会更宽不会更窄，但用户确认环节可见对照）与黑名单交叉兜底。
- [本地预整理的"前缀合并"把 `^git push.*$` 与 `^git push --force.*$` 错并] → 前缀合并仅在"短规则整体是长规则的字符串前缀"时触发，此时短规则本就覆盖长规则（`^...$` 锚定下前缀规则更宽是充要条件），合并无损。
- [AI 调用延迟（秒级）阻塞 B 路径的批量处理节奏] → B 路径加 loading 态；AI 超时走 `chat(timeout:)` 短超时（建议 15s）后静默降级；不加节流（用户已确认方案 i）。

## Migration Plan

纯客户端功能新增，无数据迁移：存量白名单规则原样保留，首次使用「AI整理」即可就地收敛。回滚 =  revert 代码，白名单数据格式无变化（仍是字符串列表），无状态残留。

## Open Questions

- denylist 交叉校验样本集的具体命令清单在实现时从 `defaultDenylist` 逐条派生并评审——属于静态数据细化，不影响架构与任务拆分。
