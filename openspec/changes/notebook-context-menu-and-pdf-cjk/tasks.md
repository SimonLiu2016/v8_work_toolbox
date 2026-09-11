## 1. PDF 导出 CJK 字体保真

- [x] 1.1 在 `export_service.dart` 实现离线 CJK 字体加载器：查找 macOS `/System/Library/Fonts/Supplemental/Arial Unicode.ttf`，结果以单例 `pw.Font?` 缓存；找不到则回退内置字体且不发起网络请求
- [x] 1.2 在 `_exportToPdf` 中同时完成两处修正：注入 `pw.Document(theme: pw.ThemeData.withFont(base: cjkFont))`，**并**给每处 inline `TextStyle`（标题、段落、列表、代码块、元信息）补充 `font:`（经 `_withCjk()` 统一构造）—— 渲染端 `Text._preProcessSpans` 用 `style.font!` 取字体，inline 样式不带 `font` 会丢失中文字形，只注入主题不生效
- [x] 1.3 新增 `test/notebook_pdf_export_test.dart`：断言含中文内容导出后 PDF 字节中实际嵌入了 CJK 字体（而非仅断言导出成功），并覆盖"系统字体不可用"时回退不崩溃

## 2. 单篇笔记子窗口与跨窗口刷新

- [x] 2.1 在 `main.dart` 处理 `subWindowArgument.startsWith('note:')`，启动 `_SingleNoteWindowApp` 渲染目标笔记
- [x] 2.2 在 `notebook_page.dart` 增加子窗口启动器：`WindowController.getAll()` 匹配 `note:<id>` 则前置，否则 `WindowController.create` 新建
- [x] 2.3 主窗口接入 `window_manager` 焦点事件，重新获得焦点时调用 `_refresh(silent: true)` 以感知子窗口中的编辑

## 3. 右键上下文菜单（10 项）

- [x] 3.1 在中间列卡片现有 `InkWell` 上添加 `onSecondaryTapDown`，捕获坐标并触发 `_showNoteContextMenu`
- [x] 3.2 构建 macOS 风格菜单：10 项、带图标与分隔线；`isPinned` 决定"添加/从快捷方式中移除"文案，废纸篓视图显示红色"粉碎笔记"
- [x] 3.3 实现基础动作：新建笔记（聚焦标题）、切换 `isPinned` 置顶、创建任务（追加 todo delta op）、复制笔记链接（深链 + markdown 格式）、删除（软删 + Undo SnackBar / 粉碎确认）
- [x] 3.4 实现笔记本选择器弹窗与"移动笔记到…"动作（`updateNote(notebookId:)`，刷新当前与目标视图）
- [x] 3.5 实现共享弹窗：复制 Markdown、复制纯文本、另存离线 HTML
- [x] 3.6 实现导出弹窗：格式选择（PDF/Markdown/HTML/TXT）+ 目录选择
- [x] 3.7 在 `note_store.dart` 增加附件提取工具方法，按原始文件名另存、重名追加序号；实现"将附件保存到文件夹…"动作
- [x] 3.8 各动作反馈统一使用 SnackBar，成功/失败均给出提示

## 4. 验证、构建与部署

- [x] 4.1 运行单元测试与集成测试，覆盖右键动作与 PDF 中文字体嵌入
- [x] 4.2 运行 `flutter build macos --release` 并通过 `ditto` 更新 `/Applications/V8WorkToolbox.app`
- [ ] 4.3 手动验证：右键菜单 10 项逐一点击；子窗口打开/复用/前置；子窗口编辑后主窗口中间列刷新
