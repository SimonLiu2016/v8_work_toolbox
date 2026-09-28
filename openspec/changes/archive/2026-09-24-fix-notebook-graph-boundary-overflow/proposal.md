## Why

在“工作笔记本”右侧打开“知识星图”时，由于 `CustomPaint` 默认未限制绘制裁剪范围，当 3D 星系旋转至左侧或靠近左边界的核心节点常驻文字胶囊伸展时，绘制内容会越过星图边界溢出到左侧主笔记编辑器区域，破坏白底纸质编辑器的视觉整洁与交互纯粹性。

## What Changes

- 在 `KnowledgeGraphView` 的绘制主体（`_graphBody`）增加物理视口裁剪 `ClipRect`，彻底阻断任何星体、连线、外发光光晕及文字胶囊越界溢出到左侧笔记区。
- 优化核心节点与悬停节点的常驻文字标签坐标计算（`_drawNodeLabel`），引入双向安全内边距边界钳制（`clamp`），避免靠近左侧边缘的节点标签被生硬截断，提升视觉平滑度。
- 微调 3D 球体分布自适应基准半径，使其在默认 420px 视口宽度下获得更聚拢、舒适的视觉展示效果。

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `notebook-tool`: 规范知识星图视图在侧边栏面板内的视口裁剪与边界约束表现，保证 3D 渲染内容严格局限于星图容器内部。

## Impact

- `lib/tools/notebook/ui/knowledge_graph_view.dart`: 增加 `ClipRect` 裁剪并优化标签定位计算。
- 单元测试与端到端渲染回归测试。
