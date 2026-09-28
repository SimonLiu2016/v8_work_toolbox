## Context

在 `KnowledgeGraphView` 中，3D 球体视角由 `_rotationY`（方位自转）和 `_rotationX`（俯仰角）驱动。目前自转增量固定为每帧 0.0035 弧度。此外，`_autoRotate` 状态在用户鼠标点击星体时并未被改变，只有在平移手势 `onPanStart` 时才置为 false。

## Goals / Non-Goals

**Goals:**
- 将 `_animController` 驱动下的每帧自转步长从 `0.0035` 调整为 `0.0012`。
- 在 `_handleTap` 命中有效节点时，取消 `_resumeTimer` 并将 `_autoRotate` 设为 `false`，锁定视角。
- 在 `MouseRegion.onExit` 中，触发 `_autoRotate = true`，让鼠标离开星图面板后自然恢复静谧自转。

**Non-Goals:**
- 不破坏原有的手势拖拽自由 3D 旋转与鼠标滚轮缩放功能。
- 不影响节点跳转主窗口笔记列表联动逻辑。

## Decisions

### 决策 1: 自转角速度参数调优
- **选择**: `_rotationY += 0.0012;`
- **对比**: 0.0035 转动较明显，容易在短时间内让目标转到背面；0.0012 呈现星空慢速巡航感，约 90 秒自转半周，观感极为舒适。

### 决策 2: 点击与移出的自转状态机
- **选择**:
  - 点击节点成功（`n != null`）：`_resumeTimer?.cancel(); setState(() => _autoRotate = false);`
  - 鼠标移出星图（`onExit`）：`_resumeTimer?.cancel(); setState(() { _hoverId = null; _autoRotate = true; });`
- **原因**: 符合直觉预期——当用户在星图中探究某个具体节点时保持静止；当用户将光标移开（例如回到左侧编辑器打字或阅读）时，星图作为侧边背景动态展示，恢复呼吸感自转。

## Risks / Trade-offs

- **[Risk] 点击空白区域的处理** → **Mitigation**: 点击星图空白处不暂停自转，或仅在命中具体节点时暂停，保持背景操作的轻量化。
