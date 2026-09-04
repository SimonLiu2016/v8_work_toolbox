## Why

应用冷启动时出现数秒黑屏与卡顿，根因是工作区容器在第一帧立即初始化所有已注册工具，且「智能磁盘瘦身」在 `initState` 阶段自动执行了全盘递归扫描，重度阻塞了 Flutter UI 渲染流水线。系统瘦身属于重度分析任务，必须由用户主动点击触发；同时工作区应当对各工具页面实行按需懒加载。

## What Changes

- **用户主动触发瘦身扫描**：
  - 移除 `SmartDiskSlimmerPage` 在 `initState` 中的自动 `_startScan()` 调用；
  - 增加精美的「就绪待扫」欢迎状态页，显示磁盘用量图与醒目的「🚀 开始全盘智能分析」大按钮；
  - 只有在用户主动点击按钮后，才启动三阶段渐进式扫描。
- **工作区页面按需懒加载 (Lazy Loaded IndexedStack)**：
  - 重构 `AppShell` 的右侧工作区容器，维护已访问工具集合 `_activatedToolIndices`；
  - 未点击过的工具仅占位 `const SizedBox.shrink()`，点开后才真正挂载实例化并常驻状态；
  - 确保整个应用冷启动在 50ms 内秒开，彻底消除黑屏卡顿。

## Capabilities

### New Capabilities

### Modified Capabilities
- `disk-analyzer`: 将分级扫描改为用户显式触发模式，提供就绪待扫与扫描中状态流转。
- `workspace-navigation`: 主工作区容器支持工具页面按需懒加载挂载，避免冷启动全部实例化。

## Impact

- `lib/tools/slimmer/smart_disk_slimmer_page.dart`: 增加空闲就绪态视图与用户触发流程。
- `lib/shell/app_shell.dart`: 改造为懒加载 `IndexedStack`。
