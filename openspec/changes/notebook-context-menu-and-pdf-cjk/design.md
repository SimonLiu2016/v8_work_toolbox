## Context

当前笔记应用中间列采用 `ListView.builder` 渲染笔记卡片，卡片是绑定了 `onTap` 的 `InkWell`（`notebook_page.dart` 约 1126 行起），除批处理模式下的 `Checkbox` 外不含任何输入控件或手势竞技场，因此在其上叠加右键监听不会与右列 `NoteEditor` 的手势/焦点机制相互影响。应用导出服务 `ExportService._exportToPdf` 使用 `package:pdf` 默认字体，不支持中文字形。

## Goals / Non-Goals

**Goals:**
- 在中间列笔记卡片上实现完整的 10 项右键上下文操作菜单，所有菜单项具备明确功能落地。
- 利用 `desktop_multi_window` 实现单篇笔记在独立桌面窗口中打开，已打开则前置而非重复创建。
- 子窗口中的编辑能被主窗口中间列感知。
- 支持将笔记附件与内嵌图片一键批量另存至本地文件夹。
- 建立无需外部网络的本地 CJK 字体加载流水线，保证 PDF 导出中文显示保真。

**Non-Goals:**
- 不引入外部云端或第三方服务器中转（保持 100% 本地离线隐私安全）。
- 不更改底层 SQLite / Drift 核心表结构（复用已有的 `isPinned`、`Attachments` 等字段）。
- 不实现演示模式、笔记复制到/创建副本（本轮范围外，见 proposal 的移除说明）。
- 不实现编辑器层面的笔记克隆，因此不需要处理附件路径改写问题。

## Decisions

### 决策 1：右键菜单触发与定位机制
- **选择**：在中间列卡片现有的 `InkWell` 上直接添加 `onSecondaryTapDown: (details) => _showNoteContextMenu(details.globalPosition, note)`，通过 `showMenu<String>` 弹出 macOS 风格浮动菜单。
- **理由**：`InkWell` 原生支持 `onSecondaryTapDown`，无需外层再包 `GestureDetector`。中间列卡片是纯展示控件，不存在焦点竞争。
- **备选方案**：外层 `GestureDetector`。弃用原因：多包一层，且 `showMenu` 已在底层处理手势。

### 决策 2：独立子窗口参数协议与复用
- **选择**：扩展 `main.dart` 中的子窗口路由，支持 `note:<noteId>` 参数：
  ```dart
  if (isSubWindow && subWindowArgument.startsWith('note:')) {
    final noteId = subWindowArgument.substring(5);
    runApp(_SingleNoteWindowApp(noteId: noteId));
  }
  ```
- **复用**：创建前先 `WindowController.getAll()` 匹配 `arguments == 'note:<id>'`，命中则 `show()` 前置。与 `registry.dart` 中笔记本窗口"已开则前置"的既有模式一致。
- **备选方案**：现有窗口内拆分视图。弃用原因：用户明确要求"在新窗口中打开笔记"，多窗口更符合 macOS 生产力工作流。

### 决策 3：跨窗口数据同步采用焦点驱动刷新
- **选择**：主窗口接入 `window_manager` 的焦点事件，在窗口重新获得焦点时调用 `_refresh(silent: true)`。子窗口保存走同一个 SQLite 文件，因此焦点驱动的按需刷新即可保证列表标题与摘要一致。
- **范围界定**：本决策只覆盖**中间列列表**的刷新，不覆盖"主窗口正在编辑同一篇笔记"的场景。该场景下主窗口的编辑器持有未落盘草稿，刷新列表不改变编辑器内容，行为可接受。
- **为何不轮询**：固定间隔轮询会持续读盘，焦点驱动是用户可见操作的直接结果，代价更低且语义更明确。
- **备选方案**：在 spec 中降级为"主窗口需手动刷新"。未采用：成本极低（约十余行监听代码），不值得牺牲体验。

### 决策 4：PDF 导出 CJK 字体加载与生效范围
- **选择**：在 macOS 上优先加载系统自带 `/System/Library/Fonts/Supplemental/Arial Unicode.ttf`（读取约 30ms），若不存在或异常则回退至 `package:pdf` 内置字体并**不发起任何网络请求**。
- **关键修正——inline 样式优先**：`_exportToPdf` 当前为每个 widget 手写 inline `TextStyle`（如 `pw.Text(..., style: pw.TextStyle(fontSize: 24, fontWeight: bold))`）。在 `package:pdf` 中 inline 样式优先于 `pw.ThemeData.withFont` 注入的 base，因此**仅注入主题不会生效，中文仍是方块**。必须给每处 inline 样式补充 `fontFamily`（或抽取为统一的 `pw.FontStyle` 常量复用）。
- **缓存**：在 `ExportService` 中维护单例 `pw.Font? _cachedCjkFont`，首次加载后常驻内存。
- **备选方案**：`PdfGoogleFonts.notoSansSC` 在线兜底。弃用原因：与 Non-Goals 的"100% 本地离线"冲突，且离线场景下必然失败。

### 决策 5：附件另存保留原始文件名
- **选择**：按 `Attachments.filename` 列复制文件（磁盘上的 `localPath` 使用 `$id$ext` 命名，仅用于内部寻址），重名时在末尾追加序号。
- **理由**：内部命名对用户无意义，另存后应可辨认。

### 决策 6：菜单反馈统一使用 SnackBar
- **选择**：置顶、创建任务、复制链接、删除撤销、附件另存、移动等反馈统一走 `ScaffoldMessenger.showSnackBar`，其中删除笔记使用带 Undo action 的 SnackBar。与 `note_editor.dart` 既有反馈方式一致。

## Risks / Trade-offs

- **[PDF 输出体积显著膨胀]** → `Arial Unicode.ttf` 约 22MB，`pw.Font` 会将其嵌入每个导出的 PDF，产物体积从数百 KB 增至约 10MB+。这是离线保真的直接代价，无法通过分包避免（`package:pdf` 不支持增量字体子集）。取舍是明确的：优先保真，接受体积。
- **[子窗口与主窗口同时编辑同一篇笔记]** → 无冲突解决机制。后保存者覆盖先保存者，且不提示。已在决策 3 中限定为已知且可接受的边界。
- **[inline 样式修正遗漏]** → 若只注入主题而未补 `fontFamily`，会得到"测试通过但中文仍是方块"的假修复。因此任务 1.3 的测试必须断言字体实际嵌入 PDF，而非仅断言导出成功。
- **[测试环境字体不可用]** → CI 或非 macOS 环境可能缺少 `Arial Unicode.ttf`。测试需覆盖"无系统字体"路径，确保回退不崩溃。
- **[焦点监听未覆盖全部入口]** → 若子窗口不是通过焦点切换回到主窗口（例如主窗口始终在前台但子窗口在另一台显示器），中间列不会刷新。属于边缘场景，不额外处理。
