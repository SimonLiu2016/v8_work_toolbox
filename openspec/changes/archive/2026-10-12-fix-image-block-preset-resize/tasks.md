## 1. 自实现图片块组件

- [x] 1.1 新建 `lib/tools/notebook/ui/components/note_image_block_component.dart`，实现 `BlockComponentBuilder`，`build(ctx)` 返回自己的 widget（`node` 取自 `BlockComponentContext.node`）。三处包内符号够不着，自带替换：`isBase64`/`isURL`（`string_validator` 只是间接依赖，直接 import 会被 `depend_on_referenced_packages` 拦）、`dataFromBase64String`（所在 `base64_image.dart` 未从包公开导出）、`AlignmentExtension.fromString`
- [x] 1.2 State 里宽度每次 build 从 `node.attributes[ImageBlockKeys.width]` 现读；`didUpdateWidget` 按新落库值重算拖拽状态（含"拖拽中被预设打断"这一路，丢弃 in-flight 偏移，否则松手会用旧起点覆盖预设）
- [x] 1.3 保留 `BlockSelectionContainer` 包裹与 `menuBuilder` 挂载（`MouseRegion` + `ValueListenableBuilder` 悬停显隐）。`menuBuilder` 改用我们自己的 `NoteImageBlockMenuBuilder` typedef——包内那个的第二形参类型是它的 State，匹配不上
- [x] 1.4 三种 src 均支持：base64 / http(s) URL / 本地文件，本地文件带 `gaplessPlayback` 与错误占位。`SelectableMixin` 需要补齐 `start`/`end`/`getPositionInOffset`/`shouldCursorBlink` 四个成员（前三个包内未导出实现，照其语义自写）

## 2. 拖拽缩放 1:1 复刻

- [x] 2.1 左右各 5px 热区，`onHorizontalDragStart` 记 `_initialOffset`，`onHorizontalDragUpdate` 写 `pendingDelta` 并 `setState` 做实时预览
- [x] 2.2 居中对齐时位移量 `*= 2.0`（左右各扩一半），包内既有补偿，删了会让居中图越拖越偏
- [x] 2.3 `onHorizontalDragEnd` 提交 `displayedWidth`、重置拖拽状态，并回调写文档树（`transaction.updateNode`）
- [x] 2.4 把手只在悬停时可见，`SystemMouseCursors.resizeLeftRight`
- [x] 2.5 单测（`test/note_image_block_component_test.dart`，8 例）：宽度下限 30、居中 ×2 补偿、左右热区的符号约定、align 三值与 null/未知值兜底。算术抽成顶层纯函数 `displayedImageWidth`，不依赖 widget 树

## 3. 统一宽度基准

- [x] 3.1 提供 `editorContentWidth(context)`：优先块自身 `RenderBox.size.width`，取不到再退回内容区 `MediaQuery`
- [x] 3.2 `note_image_menu.setWidth(percentage)` 改用该基准，不再用整窗 `MediaQuery.of(context).size.width`
- [x] 3.3 拖拽提交的宽度与预设算出的像素值可互相复现——实机验证通过
- [x] 3.4 `clamp(100.0, contentWidth)` 的下界保留，注释说明它兜的是"窄窗口下 25% 会被压到不可见"

## 4. 接线与回归

- [x] 4.1 `note_editor.dart` 的 `ImageBlockKeys.type` 换成 `NoteImageBlockComponentBuilder`，`showMenu: true` + `menuBuilder` 接线不变
- [x] 4.2 `align` 三项走 `build` 现算，不经过被修的缓存（代码路径上仍成立；`imageAlignmentFromString` 的兜底行为由单测覆盖）
- [x] 4.3 浮条的「复制路径」「删除图片」仍作用于 `menuBuilder` 收到的活 `node`——挂载方式未改
- [x] 4.4 运行 `flutter analyze` 与全量测试，确认零回归——`flutter analyze lib/` 零 error；全量 `+1013 ~3 -13`，失败集合与改动前**逐字相同**（10 个文件、13 个用例），通过数 +8（新增 8 个宽度算术用例）
- [x] 4.5 实机验证通过：预设四档即时变化、100% 铺满内容区、拖左右边缘仍可调、拖到最宽与点 100% 等宽、旧笔记图片正常显示且可缩放、新粘的微信截图同样可缩放、居左/居中/居右与复制路径/删除照旧

## 5. 部署

- [x] 5.1 运行 `./scripts/deploy_local.sh` 并重新启动应用——部署成功，新 PID 17995，notebook.db 正常打开
- [x] 5.2 核对新构建 AOT 快照已变化（74e29632 → 949d54e4）、strict 签名校验通过
