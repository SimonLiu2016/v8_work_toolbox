## 1. 核心导航联动与跳转修复 (NotebookPage)

- [x] 1.1 修改 `_openNoteById` 逻辑，在刷新前查询目标笔记归属的笔记本与分组，同步更新侧边栏选中状态
- [x] 1.2 在 `_openNoteById` 中重置搜索词（`_searchQuery = ''`）、清除标签过滤（`_selectedTagId = null`）并退出批量模式
- [x] 1.3 在 `_openNoteById` 中确保刷新完成后稳妥持久化选中 `_selectedNote = note`，防止界面闪烁

## 2. 自动化测试验证

- [x] 2.1 编写 `test/notebook_cross_view_jump_test.dart` 测试跨笔记本跳转场景下的导航状态同步与选中保持
- [x] 2.2 运行全套相关测试确保零回归

## 3. 应用构建与部署验证

- [x] 3.1 编译打包 macOS Release 版本 (`flutter build macos --release`)
- [x] 3.2 覆盖替换本机应用 `/Applications/V8WorkToolbox.app` 并启动验证
