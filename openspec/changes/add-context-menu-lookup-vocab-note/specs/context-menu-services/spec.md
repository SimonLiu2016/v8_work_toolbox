## Purpose

提供 macOS 系统级服务（NSServices）集成和全局热键注册，使用户可从任意外部 macOS 应用（浏览器、PDF 阅读器、文本编辑器等）的右键菜单触发 V8WorkToolbox 的查词和保存笔记功能，无需切换至主应用窗口。

## ADDED Requirements

### Requirement: 右键菜单服务注册

V8WorkToolbox SHALL 在 macOS 右键菜单的「服务」子菜单中注册「查词」和「保存笔记」两条系统服务，使其在任何支持文字选区的外部应用中可见并可触发。

#### Scenario: 服务在浏览器中可用

- **WHEN** 用户在 Safari 或 Chrome 中选中任意文字并右键点击
- **THEN** 右键菜单的「服务」子菜单中显示「查词 — V8」和「保存笔记 — V8」两项

#### Scenario: 服务在 PDF 阅读器中可用

- **WHEN** 用户在 Preview 或其他 PDF 阅读器中选中文字并右键点击
- **THEN** 「服务」子菜单中同样显示上述两项服务

#### Scenario: 应用未在前台时触发服务

- **WHEN** V8WorkToolbox 已在后台驻留（托盘模式）且用户在外部 App 触发服务
- **THEN** 应用自动唤起并处理该服务请求，无需用户手动切换至 V8WorkToolbox

### Requirement: 全局热键查词

V8WorkToolbox SHALL 注册全局热键 `⌥D`，在任何前台应用中按下时触发查词浮窗，读取当前选区或剪贴板中的文字作为查询词。

#### Scenario: 按下 ⌥D 触发查词

- **WHEN** 用户在任意应用中选中文字后按下 `⌥D`
- **THEN** 查词浮窗弹出并以选中文字作为查询词展示结果

#### Scenario: 无选区时按下 ⌥D

- **WHEN** 用户按下 `⌥D` 但没有选中任何文字
- **THEN** 查词浮窗弹出并显示空查询提示，光标聚焦在搜索框中等待输入

### Requirement: 全局热键保存笔记

V8WorkToolbox SHALL 注册全局热键 `⌥S`，在任何前台应用中按下时触发笔记保存流程，读取当前选区文字。

#### Scenario: 按下 ⌥S 触发保存笔记

- **WHEN** 用户在任意应用中选中文字后按下 `⌥S`
- **THEN** 笔记捕获流程启动，将选中文字保存至默认笔记本，并短暂显示确认提示

#### Scenario: 热键不与现有热键冲突

- **WHEN** 应用启动并注册 `⌥D` 和 `⌥S`
- **THEN** 不影响现有 `⌥Space` 热键的正常工作

### Requirement: 选区文字传递

服务触发时，选区文字 SHALL 完整地从外部应用传递至 V8WorkToolbox 处理层，不丢失内容。

#### Scenario: 服务处理选区文字

- **WHEN** 用户通过右键服务触发「查词」
- **THEN** 外部应用的完整选区文字通过 NSPasteboard 传递至 V8WorkToolbox，查词浮窗以该文字为查询词打开

#### Scenario: 热键读取选区

- **WHEN** 用户按下 `⌥D` 或 `⌥S` 时有文字被选中
- **THEN** 系统通过模拟 ⌘C 将选区复制至剪贴板，V8WorkToolbox 读取剪贴板内容作为输入
