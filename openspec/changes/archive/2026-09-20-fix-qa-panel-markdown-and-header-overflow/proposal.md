## Why

「问我的笔记」是浅色面板，但回答区的 markdown 渲染沿用了为暗色容器设计的默认代码底色
（`0xFF383838`），叠加近黑文字后，模型回答里被反引号包裹的内容（字段名、笔记标题、
工具调用片段）看不清。同时面板固定宽 360，header 里一段不换行的说明文字把右上角的
「清空对话」按钮挤出边界，只露出一半。

两者同源：**共享组件（`AppMarkdownView`）与浅色面板各自的默认值都绑定在暗色主题上**，
浅色容器要么漏传参数、要么没有为固定窄宽做布局。上一个 change 已用
`NotebookLightScope` 解决了输入框主题，但 markdown 的代码底色是**组件自身属性**，
主题边界覆盖不到——这类「可选参数 + 默认值合理」的缺口会随新增浅色容器复现。

## What Changes

**1. 代码底色不再假定暗色容器**

- `AppMarkdownView.codeBlockColor` 的默认值从「写死深灰」改为**从当前主题亮度推导**：
  深色主题下保持现有行为（四个既有调用点零改动），浅色主题下自动取浅灰。
- 在 `NotebookLightScope` 增加对应的浅色代码底色常量，供浅色面板显式传参（语义清晰，
  不依赖推导也被覆盖的情况）。

**2. 问答面板 header 移除溢出来源**

- 删掉 header 里那段说明文字（「基于你笔记本的内容回答，必要时可联网兜底」）——它在
  空状态时与 `_emptyHint()` 的提示重复，在有对话时纯占位，且是 360px 宽度下挤爆
  header 的唯一原因。
- header 收敛为「标题 + 清空按钮」，并给清空按钮加上防溢出约束（缩小 tap target +
  可省略），使窄宽下面板自身不再依赖父容器恰好给够空间。

## Capabilities

### New Capabilities

- `shared-markdown-theme-contrast`: 共享 markdown 渲染组件在浅色与深色容器中都须保证
  代码底色与文字颜色的对比度，其默认值由当前主题推导，而非绑定某一主题。

### Modified Capabilities

- `notebook-tool`: 「问我的笔记」面板的 header 在固定窄宽（360px）下不得溢出，回答区
  内被标记的文字须可读。

## Impact

- **修改**：`lib/components/markdown_view.dart`（默认值改为主题推导）、
  `lib/tools/notebook/ui/notebook_light_scope.dart`（新增浅色代码底色常量）、
  `lib/tools/notebook/ui/notebook_qa_panel.dart`（header 精简 + 传浅色代码底色）
- **不改**：`ai_assistant_page.dart` / `scheduled_tasks_drawer.dart` /
  `smart_disk_slimmer_page.dart` 三个调用点（暗色容器，默认值行为不变）
- **无新增依赖、无数据迁移**
