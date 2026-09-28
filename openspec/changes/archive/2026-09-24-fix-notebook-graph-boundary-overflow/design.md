## Context

`KnowledgeGraphView` 在 `notebook_page.dart` 中作为一个宽度为 420px 的右侧面板展示。在 3D 自转或用户旋转视角时，球体上的节点、发光光晕及胶囊文字标签在计算绝对屏幕投影坐标时，可能超出 $x < 0$ 或 $x > width$ 的范围。因为 `CustomPaint` 在没有显式裁切的情况下允许绘制溢出（out-of-bounds drawing），导致左侧笔记正文编辑区域受到星图图形污染。

## Goals / Non-Goals

**Goals:**
- 在 `KnowledgeGraphView` 的绘制主体包裹 `ClipRect`，对所有 CustomPaint 渲染内容实施严格物理硬裁切。
- 优化 `_drawNodeLabel` 的坐标计算：
  - 自动检测文字标签是否会超出左侧边距（$dx < 8$）或右侧边距（$dx + tp.width > size.width - 8$），采用双向安全钳制（`clamp`）或智能翻转对齐（如果右侧放不下放左侧，如果左侧仍放不下则贴紧边距放置）。
- 调整 Fibonacci 球面基础半径与视口宽度的适配关系，优化 420px 下的聚拢度。

**Non-Goals:**
- 不改变 3D 欧拉角数学模型或斐波那契球面算法的均匀性。
- 不影响多窗口模式或笔记点击跳转联动逻辑。

## Decisions

### 决策 1: 物理硬裁切 vs 软裁剪判断
- **选择**: 在 `_graphBody` 中使用 `ClipRect` 包裹 `CustomPaint`。
- **原因**: 即使算法进行软裁剪或透明度淡化，贝塞尔曲线、模糊外发光径向渐变（Radial Glow）以及微尘粒子都存在不可预期的微小像素溢出，`ClipRect` 是 Flutter 官方在 RenderObject 层面杜绝 Canvas 越界绘制的最有效保证。

### 决策 2: 文字胶囊标签智能边距钳制
- **选择**:
  ```dart
  var dx = node.screenX + 10 * node.scale;
  if (dx + tp.width > size.width - 8) {
    dx = node.screenX - 10 * node.scale - tp.width;
  }
  // 确保胶囊不会超出左右两侧安全边距
  dx = dx.clamp(8.0, math.max(8.0, size.width - tp.width - 8.0));
  ```
- **原因**: 单纯翻转在节点靠近左边缘时依然可能导致 $dx < 0$；加入 `clamp(8.0, ...)` 能让文字始终保持在星图视野内，文字完整且不发生生硬截断。

### 决策 3: 视口宽度自适应半径调整
- **选择**: 基准半径从 `(130.0 + math.sqrt(n) * 12.0).clamp(130.0, 220.0)` 微调为 `(115.0 + math.sqrt(n) * 10.0).clamp(115.0, 180.0)`。
- **原因**: 420px 宽度中点为 210px，半径 180px 配合 3D 近处透视放大（scale 1.1~1.3）后最宽处约为 $210 \pm 200$，恰好舒适地充满星图视口而不频繁撞壁。

## Risks / Trade-offs

- **[Risk] 靠近视口边缘的星体光晕可能被截断一条直线** → **Mitigation**: 缩小最大球体半径到 180px，使绝大部分星体自然旋转在安全视野内；同时 `ClipRect` 仅作为兜底屏障。
