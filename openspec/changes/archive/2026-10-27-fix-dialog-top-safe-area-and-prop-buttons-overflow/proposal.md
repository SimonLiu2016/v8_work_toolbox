## Why

在 macOS 沉浸式透明标题栏（`fullSizeContentView` + `isMovableByWindowBackground = true`）窗口环境下，系统将窗口顶部 $0 \sim 48\text{px}$ 区域捕获为原生窗口拖拽感应区。目前短视频工坊的分镜媒体预览弹窗（`_MediaPreviewDialog`）和道具资产编辑弹窗（`_PropEditorSheet`）由于贴顶或垂直外边距过小，导致顶部关键控制按钮（如右上角关闭、导出、访达定位、系统播放器打开等）落入 macOS 系统级拖动热区，鼠标点击被系统吞没，用户完全无法点击这些按钮。此外，道具编辑界面的操作区使用单行 `Row` 并排容纳了 5 个长按钮，在常规窗口宽度下触发了 `RenderFlex overflowed` 严重截断与溢出。

为了保证桌面端交互的顺畅与界面的严整，必须统一调整弹窗顶部安全交互边距，并重构道具编辑操作行以消除横向溢出。

## What Changes

1. **弹窗顶部交互安全避让（macOS 标题栏安全区）**：
   - 调整分镜媒体预览弹窗（`_MediaPreviewDialog`）的 `insetPadding`，将顶部外边距提升至至少 $52\text{px}$，使弹窗顶部栏及右上角的四个操作按钮完全脱离 macOS 原生拖拽截获区，恢复正常交互点击。
   - 调整道具资产编辑弹窗（`_PropEditorSheet`）及类似模态抽屉，为其顶部注入安全区边距（`SafeArea` 或顶部 $48\text{px}$ 避让），保证右上角关闭按钮可正常被点击。
2. **道具资产卡操作按钮防溢出流式重构**：
   - 将 `_PropEditorSheetState` 内部的参考图/生图操作行由固定 `Row` 重构为自适应流式排布（`Wrap(spacing: 8, runSpacing: 8)`），或者采用自适应紧凑按钮排布，彻底消除窄屏下的横向溢出错误。

## Capabilities

### New Capabilities
<!-- 无新增能力目录，沿用现有能力 -->

### Modified Capabilities
- `app-shell`: 明确桌面端无边框沉浸式窗口下，全屏模态弹窗与居中对话框必须避让顶部原生标题栏拖动盲区（$\ge 48\text{px}$），确保顶部操作控制按钮可交互。
- `prop-cards`: 明确道具资产卡编辑视图中的操作按钮组（添加参考图、资产库选择、尺寸选择、生图、预览等）必须支持弹性自适应排布，禁止在小宽度下产生视口溢出截断。

## Impact

- `lib/tools/ai_video_studio/ui/storyboard_board.dart`: `_MediaPreviewDialog` 的外边距设置。
- `lib/tools/ai_video_studio/ui/series_page.dart`: `_PropEditorSheet` 的顶部边距及底部参考图/生图操作按钮布局。
- 不影响底层数据模型、持久化文件格式或外部 AI API 调用接口。
