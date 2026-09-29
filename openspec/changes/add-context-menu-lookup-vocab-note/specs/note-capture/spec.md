## Purpose

提供从外部应用选区内容快速创建笔记的能力，保留原文的 Markdown 格式（标题、段落、列表、代码块、图片、表格），并在内容来源为网页时自动附加页面 URL，笔记保存至用户配置的默认笔记本。

## ADDED Requirements

### Requirement: 保存选区内容为笔记

笔记捕获服务 SHALL 将外部应用中选中的文字保存为一条新笔记，存入用户设置的默认笔记本。

#### Scenario: 通过右键服务保存笔记

- **WHEN** 用户在外部应用中选中文字后通过右键「服务 → 保存笔记 — V8」触发
- **THEN** 选区文字以 Markdown 格式保存为一条新笔记，标题取选区首行内容（截断至 60 字符），存入默认笔记本

#### Scenario: 通过热键保存笔记

- **WHEN** 用户在外部应用中选中文字后按下 `⌥S`
- **THEN** 触发与右键服务相同的保存流程

#### Scenario: 保存成功后的提示

- **WHEN** 笔记保存成功
- **THEN** 系统托盘区域显示简短成功通知（含笔记本名称），持续约 3 秒后自动消失

### Requirement: 自动附加网页 URL

当笔记内容来源于浏览器（Chrome、Safari、Firefox）时，笔记捕获服务 SHALL 自动将当前页面 URL 附加至笔记正文末尾。

#### Scenario: 从 Chrome 保存时自动获取 URL

- **WHEN** 用户在 Chrome 浏览器中选中文字并触发保存笔记
- **THEN** 系统通过 AppleScript 读取 Chrome 前台窗口当前标签页的 URL，并在笔记正文末尾附加「来源：<URL>」

#### Scenario: 从 Safari 保存时自动获取 URL

- **WHEN** 用户在 Safari 浏览器中触发保存笔记
- **THEN** 系统通过 AppleScript 读取 Safari 当前页面 URL 并附加至笔记

#### Scenario: 非浏览器来源时弹出 URL 输入框

- **WHEN** 笔记内容来源于非浏览器应用（如 PDF 阅读器、终端等）
- **THEN** 笔记保存后弹出小对话框显示「是否附加来源 URL？」，用户可选择填写或跳过

#### Scenario: AppleScript 获取 URL 失败时降级

- **WHEN** AppleScript 读取浏览器 URL 失败（如权限拒绝、浏览器未响应）
- **THEN** 系统静默回退至弹出 URL 输入框的降级流程，不显示错误

### Requirement: 保留 Markdown 格式

笔记捕获服务 SHALL 尽量将选区文字的结构（标题层级、段落分隔、粗斜体、列表、代码块）以 Markdown 语法保留在笔记正文中。

#### Scenario: 保留纯文本段落结构

- **WHEN** 选区内容包含多个段落
- **THEN** 笔记以空行分隔段落，保留原有换行结构

#### Scenario: 保留富文本标题

- **WHEN** 选区来源支持富文本（如 Safari 中的 HTML 内容），且内容含标题元素
- **THEN** HTML 标题标签（H1–H6）转换为对应 Markdown 标题语法（# 至 ######）

#### Scenario: 保留图片引用

- **WHEN** 选区含图片且来源为网页
- **THEN** 图片以 Markdown 图片语法 `![alt](url)` 保留，引用原始远端 URL

#### Scenario: 纯文本来源仅保留换行

- **WHEN** 选区来源不提供富文本（如 PDF 阅读器、终端等）
- **THEN** 笔记内容为纯文本，段落换行结构尽量保留，不强行推断 Markdown 格式

### Requirement: 配置默认笔记本

笔记捕获功能 SHALL 在设置面板中提供「设为默认笔记本」功能，让用户指定保存笔记的目标笔记本，并支持在首次使用时引导配置。

#### Scenario: 设置默认笔记本

- **WHEN** 用户在笔记捕获设置中选择一个笔记本并点击「设为默认」
- **THEN** 该笔记本被标记为笔记捕获的默认目标，后续保存操作使用此笔记本

#### Scenario: 首次使用时引导配置

- **WHEN** 用户首次触发保存笔记且尚未配置默认笔记本
- **THEN** 系统弹出引导对话框要求用户选择一个默认笔记本后再继续保存
