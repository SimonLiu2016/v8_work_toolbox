## Why

图片块选中后，点顶部浮条的 25% / 50% / 75% / 100% 预设**没有任何反应**——但同一张图用鼠标拖左右边缘是能改变大小的。

根因不在我们自己的代码，而在 `appflowy_editor` 6.2.0 内部的 `ResizableImage`：它把传入的 `width` 抄进自己的 State 字段 `imageWidth`，**且只抄一次**：

```dart
// appflowy_editor-6.2.0/.../resizable_image.dart
class _ResizableImageState extends State<ResizableImage> {
  late double imageWidth;

  @override
  void initState() {
    imageWidth = widget.width;   // 只在"出生"时读
  }

  @override
  Widget build(BuildContext context) {
    SizedBox(width: max(30, imageWidth - moveDistance), ...)  // 渲染用 imageWidth
  }
}
//  整个文件没有 didUpdateWidget
```

于是两条改变宽度的路径命运不同：

```
拖拽边缘 ──► 直接改 imageWidth + setState ──► 屏幕跟着变 ✓
点 25%  ──► updateNode 写文档树 ✓ → ImageBlockComponent 重build ✓
              → ResizableImage(width: 300) 但 State 已存在，initState 不再跑
              → imageWidth 还是旧值 ──► 屏幕不变 ✗
```

**attribute 写对了、渲染层也读对了，只有那个 StatefulWidget 不肯更新自己的字段。** 这不是本次或以往任何改动引入的——它对所有图片都成立，包括「插入图片」按钮插进来的图，只是用户第一次在预设缩放上撞见。

`appflowy_editor` 的 latest 就是 6.2.0，上游没有修复可升；包也没有提供替换 `ResizableImage` 或给它塞 `key` 的扩展点（`ImageBlockComponentWidgetState.createState()` 返回具体类型，`imageKey` 挂在 `Padding` 上而非 `ResizableImage`）。

## What Changes

- **自实现图片块组件**：让 `ImageBlockKeys.type` 走我们自己的 `BlockComponentBuilder`，不复用包内部的 `ResizableImage`。新组件从 `node.attributes` 现读宽度，并实现 `didUpdateWidget` —— 这是修掉根因的那一步。
- **拖拽手柄 1:1 复刻**：左右 5px 热区、悬停才显现的把手、拖拽中实时预览、松手才落库、最小宽度 30、居中对齐时位移量 ×2 补偿。逐个对齐包的行为，不做"简化版"——半套拖拽比不拖更烦。
- **统一宽度基准**：拖拽与预设两路都以**编辑器内容区宽度**为基准。当前两者不同源（拖拽用 State 里的像素值，预设用 `MediaQuery` 的整窗宽度），导致"拖到最宽"与"点 100%"结果不一致。
- **修正主 spec 的一处既有偏差**：现描述写"right-click context menu"与"Auto"，而实现是顶部悬浮条、四档预设、无 Auto。 delta 一并改正，避免归档时把错描述固化。

## Capabilities

### New Capabilities

- 无。

### Modified Capabilities

- `notebook-editor`: 「Block-based rich text editing with AppFlowy Editor」的图片操作场景——预设缩放在文档树变更后必须反映到屏幕，拖拽与预设共用同一宽度基准，同时把该场景对控件形态的描述修正为与实际一致。

## Impact

- **Flutter 层**：新增 `lib/tools/notebook/ui/components/note_image_block_component.dart`（builder + widget + state + 自己的 resizable 逻辑）；`note_editor.dart` 的 `blockComponentBuilders` 中 `ImageBlockKeys.type` 换成新 builder；`note_image_menu.dart` 的 `setWidth` 改用内容区宽度为基准。
- **依赖**：仍依赖 `appflowy_editor` 的 `BlockComponentBuilder` / `BlockComponentContext` / `Selection` 等公开 API；**不再复用**包内的 `ImageBlockComponentBuilder`、`ResizableImage`、`AlignmentExtension`（最后一个改用我们自己的小工具）。
- **持久化**：图片块的 `width` / `align` attribute 语义不变，仍是 `ImageBlockKeys.width`（double 像素）与 `ImageBlockKeys.align`（字符串）。只是同一个值现在能被预设按钮正确渲染出来。**无 schema 变更、无数据迁移。**
- **非目标**：不加 "Auto" 档（spec 原文提到但从未实现，本次只修正描述不补功能）；不做图片裁剪、旋转、滤镜；不改附件块与思维导图块的渲染。
