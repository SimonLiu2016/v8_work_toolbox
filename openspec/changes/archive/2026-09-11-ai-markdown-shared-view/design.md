## Context

本项目的 markdown 渲染需求来自三处 AI 输出界面。上一个变更 `slimmer-ai-markdown-render` 已在 `smart_disk_slimmer_page.dart:373` 内联了约 33 行 `MarkdownStyleSheet`；若另外两处照搬，同一份样式将有 3 份拷贝，改一处漏两处。本变更将其收敛为单一共享组件。

`lib/` 下现存的 3 处 `SelectableText` 中，只有 2 处承载 AI 输出：

- `ai_assistant_page.dart:338` — AI 回答气泡（背景 `AppTheme.bgCard` = #2D2D30）
- `scheduled_tasks_drawer.dart:299` — 资讯快报卡片（`AppCard` 背景同为 `AppTheme.bgCard`）

第三处 `ai_assistant_page.dart:290` 是**用户输入气泡**，应保持纯文本渲染：用户输入 `**hello**` 时应当原样显示，而不是被解析成加粗。这一条是明确的边界，不能"顺手"一起改掉。

`AppTheme.fontBody` 为 `fontSize: 13, height: 1.45`，而既有聊天气泡用 `fontSize: 14, height: 1.6`。共享组件需要一个 `TextStyle` 覆盖入口，否则两处既有字号会被静默改掉。

## Goals / Non-Goals

**Goals:**
- 单一共享组件承载全部 markdown 样式，消除重复
- 三处 AI 输出界面渲染一致，且与 AppTheme 颜色体系保持协调
- 支持文本选择与复制（既有行为，不可退化）

**Non-Goals:**
- 不解析或渲染用户输入气泡（保持 `SelectableText`）
- 不引入链接跳转、图片加载、自定义标签等扩展交互
- 不改动 AI 返回内容的 prompt 或协议
- 不为 markdown 渲染引入新的第三方依赖（`flutter_markdown` 已由前置变更引入）

## Decisions

### 1. 组件命名为 `AppMarkdownView`，置于 `lib/components/markdown_view.dart`

**选择**: `lib/components/markdown_view.dart` 中的 `AppMarkdownView`

**理由**: `lib/components/` 是项目既有的共享组件目录（`app_components.dart` 即在其中）。不使用 `lib/widgets/`，因为项目并无该目录，引入新目录层级会增加发现成本。

**替代方案**: 放入 `lib/tools/ai_assistant/` — 拒绝，该组件将被 slimmer 页面复用，放在单个工具目录下会造成反向依赖。

### 2. 使用 `MarkdownBody` 而非 `Markdown`

**选择**: `MarkdownBody`（不带 `ScrollView`）

**理由**: 三个调用点外层均已各自提供滚动容器（`SingleChildScrollView` / `Expanded` / `ListView`）。使用带 `ScrollView` 的 `Markdown` 会引入嵌套滚动，出现双滚动条或手势冲突。组件应保持"纯内容渲染"职责，滚动交给调用方。

### 3. 代码块背景色由调用方通过参数注入，不写死

**选择**: `AppMarkdownView` 暴露 `codeBlockColor` 参数，默认值 `AppTheme.bgCardHover`

**理由**: 代码块的视觉层次依赖它相对容器背景的对比度。三处容器背景均为 `bgCard`（#2D2D30），默认值 `bgCardHover`（#383838）足够区分。但组件不应假设容器颜色，写死会导致在浅色卡片或带边框容器中出现"代码块与背景同色"的失败情形。保留参数即为该失效模式留出出口，成本低（一个可选参数），收益是组件可迁移到任意容器。

内联 code（`` `foo` ``）沿用同一色值，仅去掉边框与内边距。

### 4. 暴露 `baseStyle` 以保留调用方既有字号

**选择**: `baseStyle` 参数默认 `AppTheme.fontBody`，所有元素样式均由其派生

**理由**: 既有聊天气泡使用 `fontSize: 14`，共享组件若强制 `fontBody`（13）会造成视觉回退。参数化后调用方传入自身字号，样式体系仍统一。派生规则固定：

| 元素 | 派生 |
|---|---|
| `h1` / `h2` / `h3` | `baseStyle`，size 20 / 17 / 15，weight w700 / w700 / w600 |
| `p` | `baseStyle` |
| `strong` / `em` | `baseStyle`，w700 / italic |
| `code`（含 fence 代码块） | `baseStyle`，`monospace`，size 13，背景 `codeBlockColor` |
| `listBullet` | `baseStyle`，color `accent` |
| `blockquote` | `AppTheme.fontBodySecondary`，左侧 3px `accent` 半透明竖线 |

标题字号锚定绝对值而非相对 `baseStyle`，避免调用方传入大字号时标题被放大到失控。

### 5. `StatelessWidget`，样式表随 build 构造

**选择**: `AppMarkdownView` 实现为 `StatelessWidget`，`MarkdownStyleSheet` 在 `build()` 内构造

**理由**: 组件无内部可变状态，全部输入来自构造参数，没有使用 `StatefulWidget` 的理由。`MarkdownStyleSheet` 构造成本可忽略，而 `MarkdownBody` 在长对话列表中会频繁 rebuild —— 这里接受每次 build 构造一次，不引入额外的缓存或 `@memoized` 复杂度。列表场景下 `ListView.builder` 的懒构建已限制同时存在的实例数量。

不尝试 `const`：样式表依赖运行时传入的 `baseStyle`，无法做成编译期常量。

### 6. 用户输入气泡明确不改造

**选择**: `ai_assistant_page.dart:290` 保持 `SelectableText`

**理由**: 用户输入是"原样文本"而非"待格式化文档"。若同样解析 markdown，用户输入的 `` `code` `` 或 `*斜体*` 会被错误渲染，且复制回显时丢失语法。这一边界写入 spec 的 AND 子句，防止后续误改。

### 7. `selectable` 必须显式开启（默认 false，非 true）

**选择**: `AppMarkdownView` 暴露 `selectable` 参数，默认 `true`，并显式传给 `MarkdownBody`

**理由**: 读包源码确认（`flutter_markdown-0.7.7+1/lib/src/widget.dart:227`），`MarkdownWidget` 的 `selectable` 默认值是 **false**；内部渲染分支在 `builder.dart:1048` 判断 `selectable` 时才走 `SelectableText.rich`，否则退化为普通 `RichText`。

三个调用点替换前均为 `SelectableText`，用户可直接框选复制。若漏传该参数，选择能力会**静默**丢失——不报错、不告警，只有用户尝试选中文字时才发现。因此默认值必须与替换前的行为对齐（`true`），而不是跟随包的默认（`false`）。这是本变更最容易踩的一个静默回归。

### 8. 提供可选 `maxHeight`，由对话流场景启用

**选择**: `AppMarkdownView` 暴露 `maxHeight` 参数，为 null 时组件高度完全由调用方容器决定；设置后内部包一层 `ConstrainedBox + SingleChildScrollView` 自行滚动

**理由**: 既有的 `_buildMessagesList` 是**非缩放的** `ListView.builder`（`ai_assistant_page.dart:263`），消息容器没有最大高度约束。这意味着一条极长的 AI 回答会无限撑高自己那个气泡，把对话列表整个向上顶。原 `SelectableText` 版本已存在同一问题，本变更不改变该行为，但既然要新写组件，提供参数化出口成本几乎为零。

采用"调用方启用"而非"组件内默认限制"，是因为两处容器的诉求不同：

- AI 研判弹窗（`smart_disk_slimmer_page.dart`）已有自己的 `SingleChildScrollView`，不应嵌套滚动 → 不传 `maxHeight`
- 对话气泡（`ai_assistant_page.dart`）在 `ListView` 中，需要限高避免顶飞输入栏 → 传 `maxHeight`

若组件内写死默认限高，弹窗场景会引入嵌套滚动的双滚动条与手势冲突（正是决策 2 拒绝 `Markdown` 的同一原因）。所以保持职责分界：滚动策略属于调用方，组件只提供能力。

## Risks / Trade-offs

**[选择能力静默丢失]** → 已处理：`selectable` 默认 `true` 对齐替换前行为（见决策 7）。

**[超长回答顶飞对话列表]** → 部分缓解：`maxHeight` 参数提供给对话流场景；资讯快报在 `ListView` 中不启用，仍会撑高单张卡片，属既有行为，未在本变更范围扩大。

**[代码块与容器背景对比不足]** → 已通过 `codeBlockColor` 参数化解；若未来出现浅色容器，调用方传色即可，组件无需改动。

**[字号派生导致聊天气泡视觉变化]** → 通过 `baseStyle` 参数吸收；落地时需逐一核对三处容器既有字号，避免静默回归。

**[共享组件掩盖单点差异]** → 三处容器的 padding / 圆角 / 边框仍由各自调用方持有，组件只负责"文本内容如何呈现"。这一切分若越界（组件开始管容器样式），会退化为又一个 `AppCard` 式的大而全组件，应避免。

**[与 `slimmer-ai-markdown-render` 的合并顺序]** → 两者均未提交。若先合并前置变更，本变更会表现为"删除 33 行内联样式 + 替换调用"，diff 更大但更干净；若直接按本变更落地，diff 更小。建议后者。
