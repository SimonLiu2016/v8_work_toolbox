## Context

当前 Smart Disk Slimmer 的磁盘扫描使用 `listSync()` 同步遍历目录，阻塞 Dart 主 Isolate 导致 UI 冻结。孤立残留检测仅依赖 `AppOrphanDetector` 的精确名称匹配，而 macOS 的 Application Support 目录名与 .app 包名之间没有强制关联，导致 VS Code (`Code`)、bilibili (`哔哩哔哩`) 等正在使用的应用被误判为"安全清理"。Stream yield 使用 `List.unmodifiable` 导致复选框无法操作。

## Goals / Non-Goals

**Goals:**
- 扫描期间 UI 保持响应（60fps 目标，30fps 最低）
- 系统性防止正在使用的应用被误判为可清理残留
- 不确定时默认保守（谨慎确认，不自动勾选）
- 用户纠正决策可持久化，形成反馈闭环

**Non-Goals:**
- 不实现完整的 macOS Spotlight/MDI 元数据集成（复杂度高，收益递减）
- 不实现实时进程检测（`lsof` 性能开销大，且需要额外权限）
- 不改变三阶段扫描的整体架构（阶段 1/2/3 的划分仍然有效）
- 不修改 AI 研判服务的逻辑（AI 诊断作为独立补充层保留）

## Decisions

### Decision 1: 异步扫描 — 定期 yield 控制权

**选择**: 在 `_calcDirSize`、`_measureDirQuick`、`_quickDirSize` 的递归遍历中，每处理 200 个文件后执行 `await Future(() {})` 让出一帧渲染时间。

**替代方案**:
- `Isolate` 隔离线程：需要序列化返回值，Dart 的 `Isolate` 不支持直接共享对象，实现复杂度高
- `list()` 异步迭代器：每个文件都 await，性能损失过大（目录遍历通常涉及数万次系统调用）

**理由**: `await Future(() {})` 是最小侵入的方案，不需要改变函数签名（仍是 `Future<int>`），只需将 `int` 返回改为 `Future<int>`，将 `void walk` 改为 `Future<void> walk`。200 个文件的间隔在实测中约 50-100ms，足以让 Flutter 渲染 3-6 帧。

### Decision 2: 多层检测 — 四层递进验证

**选择**: Bundle ID → 别名映射 → 子串匹配 → 修改时间降级，任一层命中即停止。

**检测流程**:
```
目录进入检测
  │
  ├─ Layer 1: Bundle ID 精确匹配
  │   命中 → 跳过（已安装应用）
  │   未命中 ↓
  │
  ├─ Layer 2: 别名映射 + 子串双向匹配
  │   命中 → 跳过或标记为谨慎确认
  │   未命中 ↓
  │
  ├─ Layer 3: 修改时间降级
  │   7天内 → danger（不勾选）
  │   30天内 → caution（不勾选）
  │   90天+ ↓
  │
  └─ Layer 4: 默认策略
      → caution（谨慎确认，不勾选）
```

**替代方案**:
- 纯 Bundle ID 匹配：覆盖率太低，大量 app 不用 bundle ID 做目录名
- 纯别名映射表：需要持续维护，无法覆盖所有用户安装的软件
- 纯修改时间：无法区分"属于某 app 的旧缓存"和"已卸载 app 的残留"

**理由**: 四层递进在可靠性（Bundle ID 最强）和覆盖率（修改时间兜底）之间取得平衡。默认保守策略确保即使所有层都未命中，也不会误删。

### Decision 3: 别名映射表 — 内置 + 用户学习

**选择**: 内置一份常见应用的别名映射（约 30-50 条），同时从用户反馈中持续学习。

**内置映射示例**:
```dart
const _knownAliases = {
  'code': 'visual studio code',
  'bilibili': '哔哩哔哩',
  'bravesoftware': 'brave browser',
  'adobe': 'adobe photoshop', // 子串匹配兜底
  'blizzard': 'battle.net',
  'chromium': 'google chrome',
  'dingtalkmac': 'dingtalk',
  ...
};
```

**用户学习机制**: 当用户手动取消勾选一个 `safe` 条目时，记录 `{path, appName, timestamp}` 到 `config/slimmer-keep-list.json`。下次扫描时，路径匹配的条目自动应用保留决策。

### Decision 4: JetBrains 条目区分

**选择**: 在 `_scanJetBrains` 中，根据目录来源（`Application Support` vs `Caches`）在标题中添加标识。

**实现**: 将 `title: '$family ${v.version}'` 改为 `title: '$family ${v.version}（${sourceLabel}）'`，其中 `sourceLabel` 为"配置"或"缓存"。

## Risks / Trade-offs

| 风险 | 影响 | 缓解措施 |
|------|------|---------|
| `await Future(() {})` 增加扫描总耗时 | 扫描时间可能增加 10-20% | 可接受的权衡，UI 响应性比绝对速度重要 |
| 子串匹配可能误匹配 | 如 "arc" ⊂ "search" | 仅在目录名长度 ≥ 4 字符时启用子串匹配，且要求匹配长度占比 > 50% |
| 别名映射表需要维护 | 新软件可能不在表中 | 修改时间兜底 + 用户反馈闭环形成自学习 |
| 用户标记文件可能膨胀 | 长期积累大量条目 | 定期清理已不存在目录的标记条目 |
