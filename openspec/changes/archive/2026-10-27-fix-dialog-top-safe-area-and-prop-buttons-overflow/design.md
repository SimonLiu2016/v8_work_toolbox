## Context

在 macOS 桌面平台上，应用采用沉浸式窗口架构（`titlebarAppearsTransparent = true`、`styleMask.insert(.fullSizeContentView)`、`isMovableByWindowBackground = true`）。该模式下 macOS AppKit 会把整个窗口最上方 0~48px 区域保留为原生窗口拖拽与系统事件感应区。

在短视频工坊模块中：
1. `_MediaPreviewDialog`（位于 `lib/tools/ai_video_studio/ui/storyboard_board.dart`）使用 `Dialog(insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24))`。由于顶部外边距仅 24px，弹窗标题栏与其右上角包含 4 个控制按钮（系统播放器打开、访达定位、导出、关闭）直接落在 macOS 拖拽盲区内，点击事件被原生截获，按钮失效。
2. `_PropEditorSheet`（位于 `lib/tools/ai_video_studio/ui/series_page.dart`）高度占据屏幕 85% 或更高，右上角关闭按钮位于顶部边缘，易被拖动盲区吞噬。
3. `_PropEditorSheetState` 底部的参考图操作栏包含「添加参考图」、「从资产库选择」、「尺寸比例下拉框」、「生成道具图」、「预览Prompt」等 5 个操作控件，目前使用单行 `Row`，当窗口或抽屉宽度小于 800px 时产生右侧 `RenderFlex` 溢出错误，导致按钮被截断不可见。

## Goals / Non-Goals

**Goals:**
- 调整模态对话框与抽屉的外边距与安全边距，保证所有顶部交互按钮（关闭、导出、播放等）垂直位置大于 48px，完全恢复点击功能。
- 将道具卡底部的操作按钮行重构为 `Wrap` 流式自适应排布，确保在任意抽屉或窗口宽度下都不发生横向溢出，所有按钮均可见且可用。

**Non-Goals:**
- 不全局重构 macOS AppKit 的原生窗口拖动逻辑或改动 `MainFlutterWindow.swift` 的 `isMovableByWindowBackground` 行为，以免破坏外壳标题栏的原生手势与拖拽体验。
- 不修改生图核心逻辑与 Prompt 组装逻辑。

## Decisions

### 1. 弹窗外边距安全区优化
- 在 `_MediaPreviewDialog` 中：
  将 `insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24)` 改为 `insetPadding: const EdgeInsets.fromLTRB(40, 52, 40, 24)`。这样即使在全屏或大窗口下，弹窗顶端距离屏幕最顶部也会有 52px 的安全间距，完全避让 macOS 48px 拖拽感应区。
- 在 `_PropEditorSheet` 中：
  抽屉最外层 Container/Scaffold 顶部添加安全避让 padding（例如 `padding: const EdgeInsets.only(top: 48)` 或使用带 top 约束的 `SafeArea`），防止右上角关闭按钮贴在窗口顶端。

### 2. 道具卡底部操作栏采用 Wrap 流式排布
- 将原有的：
  ```dart
  Row(
    children: [
      OutlinedButton.icon(...), // 添加参考图
      const SizedBox(width: 8),
      OutlinedButton.icon(...), // 从资产库选择
      const SizedBox(width: 8),
      ImageDimensionSelector(...), // 尺寸选择
      const Spacer(),
      FilledButton.icon(...), // 生成道具图
      const SizedBox(width: 8),
      OutlinedButton.icon(...), // 预览Prompt
    ],
  )
  ```
  改为：
  使用 `Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [...])`。
  左侧操作组与右侧生图操作组在宽度充裕时水平排开；在宽度受限时自动折为两行，生图与预览按钮优雅降级折到下一行，彻底消除 `RenderFlex overflowed by ... pixels`。

## Risks / Trade-offs

- **边距增加对垂直视口的影响**：弹窗顶部增加约 28px 边距可能略微减少视频预览区域的高度，但这能确保右上角核心操作栏立即可用，完全符合桌面应用人机交互规范。
