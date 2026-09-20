## Context

见 proposal.md「Why」。设计层需要知道的现状约束：

**`AppMarkdownView` 的形状**（`lib/components/markdown_view.dart`）：

```dart
class AppMarkdownView extends StatelessWidget {
  final Color codeBlockColor;          // 默认 AppTheme.bgCardHover = 0xFF383838
  const AppMarkdownView({..., this.codeBlockColor = AppTheme.bgCardHover, ...});

  Widget build(BuildContext context) {
    final body = MarkdownBody(data: data, styleSheet: _buildStyleSheet());
    ...
  }

  MarkdownStyleSheet _buildStyleSheet() { ... code: codeStyle ... }
}
```

关键点：`_buildStyleSheet()` 是**无 context 的实例方法**，且 `codeBlockColor` 是
`final` 字段（构造期绑定）。要让它跟随主题，必须在 `build` 里读 `Theme.of(context)`。

**`flutter_markdown` 的约束**：0.7.7 把行内 code 与 fenced code block **共用同一个
`code` 样式**（`style_sheet.dart:81` 的 `'code': code`；`widget.dart:459` 的
`formatText` 直接返回 `TextSpan(style: styleSheet.code)`）。所以一个参数同时决定两者
底色，修一处两者都对。

**四个调用点的容器底色**：

| 调用点 | 容器底色 | 现在用默认值是否合适 |
|---|---|---|
| `ai_assistant_page.dart:339` | `AppTheme.bgCard` 深 | ✓ 合适 |
| `scheduled_tasks_drawer.dart:300` | 深色气泡内 | ✓ 合适 |
| `smart_disk_slimmer_page.dart:438` | `AlertDialog(bgCard)` 深 | ✓ 合适 |
| `notebook_qa_panel.dart:262` | `Colors.white` 浅 | ✗ 串色 |

**问答面板的宽度来源**：`notebook_page.dart:1358-1361` 是
`SizedBox(width: 360, child: NotebookQaPanel(...))`——**宽度由父容器写死**，面板自身
不控制。

**header 的构成**（`notebook_qa_panel.dart:108-141`）：`Row[Icon(15) + 标题(13) +
说明文字(11) + Spacer + IconButton(默认48px tap target)]`。`Text` 无 `Expanded`、
无 `overflow`，所以它不主动让位。

**为何上次的 `NotebookLightScope` 没覆盖到**：它只覆写
`inputDecorationTheme`（`ThemeData` 的一个字段）。markdown 的代码底色是
`AppMarkdownView` 自己的构造参数，`ThemeData` 里没有对应字段能传导——这是共享组件
属性与主题字段之间的缝隙。

## Goals / Non-Goals

**Goals**
- 代码底色在浅色容器中自动正确，无需每个调用点记得传参。
- 既有三个暗色调用点**零改动、外观不变**。
- 问答面板 header 在 360px 下不溢出，且不靠"压缩文字"这种脆弱手段。

**Non-Goals**
- 不改 `flutter_markdown` 的用法或升级依赖。
- 不给 `AppMarkdownView` 加更多主题相关参数（如 `textColor`）——本次只修已被证实
  出问题的代码底色。
- 不改问答面板的宽度策略（仍由父容器写死 360）。
- 不动其他三个调用点的代码。

## Decisions

### D1: 默认值从「写死常量」改为「主题亮度推导」

`codeBlockColor` 的默认值改为 `null`（哨兵），`build` 内解析：

```dart
final Color codeBg = codeBlockColor ??
    (Theme.of(context).brightness == Brightness.dark
        ? AppTheme.bgCardHover            // 既有暗色行为，逐像素不变
        : const Color(0xFFF1F5F9));       // 浅色中性，与 NotebookLightScope.surfaceMuted 同族
```

**为什么**：默认值绑定主题字面量，是这次出错的根因。改成推导后，**未来任何浅色容器
不传参也正确**——治本。三个暗色调用点走 `Brightness.dark` 分支，取值与现在的
`AppTheme.bgCardHover` 完全相同，外观零变化。

**被否**：
- 只让 QA 面板传参（治标；下次新增浅色容器还会忘，正是 proposal 里说的复现路径）
- 把默认值直接改成浅灰（会把三个暗色调用点全搞坏）
- 让 `NotebookLightScope` 通过 `ThemeData.extensions` 传色（机制更"正统"但要新建
  `ThemeExtension` 类，为一个颜色值引入整套基础设施，过度设计）

### D2: 在 `NotebookLightScope` 增加 `codeSurface` 常量

```dart
/// 浅色容器中 markdown 代码块/行内代码的底色。
static const Color codeSurface = Color(0xFFF1F5F9);
```

QA 面板**显式传** `codeBlockColor: NotebookLightScope.codeSurface`。

**为什么**：D1 已经让默认值正确，这里看似冗余。但显式传参有三个好处：(a) 与既有
隔离模式一致——`NotebookLightScope` 的调色板常量就是给浅色面板显式用的；
(b) QA 面板的正确性不依赖"推导恰好生效"（万一将来有人给它套了别的 Theme）；
(c) 读者一眼能看出这个面板刻意选了浅色代码底色。

**被否**：只做 D1 不传（可工作，但正确性隐式，且与 `NotebookLightScope` 既有的
"面板边界显式声明"模式不一致）。

### D3: header 删除说明文字，而非压缩它

删掉「基于你笔记本的内容回答，必要时可联网兜底」。

**为什么**：三个理由叠加——
1. 它与 `_emptyHint()` 的提示（「问点关于你笔记的事 / 例如「豆浆机坏了怎么办」…」）
   **内容重复**，且空状态才是它唯一有信息量的时刻；
2. 有对话时它纯占位，却占了约 190px——是 360px 下挤爆 header 的唯一原因；
3. 压缩它（`Expanded` + `ellipsis`）要保留一段"被截断的说明"，可读性反而更差。

删除后 header 只剩「标题 + 清空按钮」，360px 下余量充足。

**被否**：
- `Expanded` + `TextOverflow.ellipsis`（保留了一段注定被截断的冗余文字）
- 把说明文字移到 `_emptyHint()` 里合并（合并后的空状态提示变长；且这是纯删减能解决
  的问题，不值得动空状态）

### D4: 清空按钮加防溢出约束，不依赖父容器给够空间

`IconButton` 包一层明确尺寸约束（`SizedBox(width/height: 32)` +
`IconButton(padding: EdgeInsets.zero, constraints: BoxConstraints())`），使 tap target
从 48px 降到 32px。

**为什么**：D3 删字后余量已够，但 header 的正确性**不应依赖"恰好没别的文字"**——
将来有人再加一个入口，48px 的固定最小点击区又会成为溢出源。显式收窄 tap target 让
这个面板对宽度变化有冗余。32px 在桌面端（鼠标操作）是可接受的点击区。

**被否**：
- 不动 tap target（D3 后能工作，但把正确性押在"没人再往 header 加东西"上）
- 用 `Tooltip` + 裸 `InkWell` 替代 `IconButton`（丢失无障碍语义，`IconButton` 自带
  button 语义与 focus 处理）

## Risks / Trade-offs

**[D1 的浅色分支选色可能与其他浅色面板不协调]** → 选 `0xFFF1F5F9`（slate-100），
与 `NotebookLightScope` 的 `surfaceMuted`（`0xFFF8FAFC`）同族但深一档，保证代码块
在浅白底上**有可见边界**而非与背景同色。这是 `codeBlockColor` 参数文档注释里已经
预见的情形（"避免代码块与容器背景同色"）。

**[D3 删掉一句话可能损失信息]** → 那句的核心信息（"必要时可联网兜底"）在
`_emptyHint` 与「改用联网检索」按钮处都有更具体的表达。删的是重复表述，不是能力。

**[D4 缩小 tap target 影响触屏]** → 本应用是 macOS 桌面端，无触屏使用场景。
32px 对鼠标操作充裕。

**[D1 改默认值影响未列出的调用点]** → 已全量 grep `AppMarkdownView(`，四个调用点
全部列在 proposal 的 Impact 里；测试里若直接构造该组件也会走新默认值，任务里包含
跑全量 `flutter test` 验证。

## Migration Plan

1. **D1+D2**：改 `markdown_view.dart` 默认值推导 + 在 `NotebookLightScope` 加
   `codeSurface` 常量。此步即使 QA 面板不传参也已修掉串色。
2. **D2**：QA 面板显式传 `codeBlockColor`。
3. **D3+D4**：精简 header + 收窄 tap target。
4. **测试与部署**：新增/修正测试 → 全量回归 → clean 构建 → 签名校验 → 经
   `/tmp/deploy` 暂存安装 → AOT 快照哈希校验 → 启动采样。

**回滚**：D1 可独立回滚（恢复写死常量即回到现状）；D3/D4 是纯 UI 删减，回滚即恢复
文字与 48px。无数据迁移。

## Open Questions

无。两个根因都在代码层确证（`codeBlockColor` 默认值写死深灰且 QA 面板未传；header
的 `Row` 在 360px 下无换行/省略机制且 `IconButton` 有 48px 最小点击区）。

一个待实机确认项记入 tasks：浅色代码底色 `0xFFF1F5F9` 与面板白底的对比度是否符合你
的观感（可调深一档到 `0xFFE2E8F0`）。
