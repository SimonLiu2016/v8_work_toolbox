# Tasks: 修复问答面板 markdown 底色与 header 溢出

> 两组独立改动：先修代码底色（组 1，改一个共享组件 + 一个调用点），再修 header
> 溢出（组 2，纯 UI 删减）。组 1 与组 2 无耦合。

## 1. 代码底色跟随主题

- [ ] 1.1 `markdown_view.dart`：`codeBlockColor` 默认值改为 `null` 哨兵，`build` 内按 `Theme.of(context).brightness` 推导——深色分支取 `AppTheme.bgCardHover`（既有行为逐像素不变），浅色分支取浅中性（design D1）
- [ ] 1.2 `notebook_light_scope.dart`：新增 `codeSurface` 常量（浅色容器中 markdown 代码底色），与既有调色板常量同族
- [ ] 1.3 `notebook_qa_panel.dart`：显式传 `codeBlockColor: NotebookLightScope.codeSurface`（design D2）
- [ ] 1.4 复核三个暗色调用点（`ai_assistant_page` / `scheduled_tasks_drawer` / `smart_disk_slimmer_page`）无需改动：它们不传参，走深色分支，取值与现在完全相同
- [ ] 1.5 新增测试：浅色 Theme 下默认代码底色为浅色、深色 Theme 下为 `AppTheme.bgCardHover`、显式传参时以传参为准

## 2. header 溢出修复

- [ ] 2.1 `notebook_qa_panel.dart`：删除 header 中的说明文字「基于你笔记本的内容回答，必要时可联网兜底」（与 `_emptyHint()` 提示重复，有对话时纯占位）（design D3）
- [ ] 2.2 清空按钮包 `SizedBox(32×32)` + `IconButton(padding: EdgeInsets.zero, constraints: BoxConstraints())`，使 tap target 从 48px 收窄到 32px，header 对宽度变化有余量（design D4）
- [ ] 2.3 新增 widget 测试：在 360px 宽容器内渲染面板（含一轮对话使清空按钮可见），断言 header 无 `RenderFlex overflowed`、清空按钮在面板边界内且命中测试可点中

## 3. 验证与收尾

- [ ] 3.1 全量回归 `flutter test`，确认无新增失败（既有失败清单需与改动前一致）
- [ ] 3.2 构建部署：`flutter clean` → `flutter build macos --release` → `codesign -v --strict` 与 `--deep` 均通过 → 经 `/tmp/deploy` 暂存安装（不用 `cp -R` 直接覆盖）→ 校验 AOT 快照哈希 → 启动采样 stderr 无未捕获异常
- [ ] 3.3 实机验证：问答面板中带反引号/代码块的回答文字清晰可读，无深灰底；header 标题与清空按钮都完整显示
- [ ] 3.4 实机确认：浅色代码底色 `0xFFF1F5F9` 的对比度观感（如偏浅可调深至 `0xFFE2E8F0`）
