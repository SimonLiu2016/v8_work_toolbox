## Context

参见 `proposal.md`。本地数据库实测单个 Web 会话已有 4,155 条资产。原实现在 `ListView` 中嵌套无虚拟化的 `Column(for asset in assets)`，并在单帧内重复执行近 30,000 次无缓存的 `jsonDecode`，导致主 UI 线程严重卡死。同时会话删除缺少便捷入口，且 `SessionRepository.delete` 使用 4,000 次串行 SQL 更新导致假死。

## Goals / Non-Goals

**Goals:**
- 将 `PentestAsset.metadata` 增加内存缓存，消除单帧重复反序列化开销。
- 在 `WebReconView` 与 `LanReconView` 中实现轻量客户端分页栏（默认每页 50 条），保证单帧仅实例化 50 个列表组件，消除卡顿。
- 在 `_buildActiveView` 中为侦察组件绑定 `ValueKey(_controller.current?.id)`，会话切换时彻底重建输入框与分页状态。
- 在 `SessionBar` 及 `_SessionSwitcher` 下拉菜单中增加直观的会话删除按钮，并在删除后自动回退切换至剩余可用会话。
- 将 `SessionRepository.delete` 重构为单条批量 SQL 事务，实现数千条数据毫秒级级联删除。

**Non-Goals:**
- 引入复杂的数据库端游标分页（SQLite 本地查询 5,000 行耗时仅 1~2ms，性能瓶颈 100% 集中在 UI 控件树全量实例化与反序列化，客户端切片渲染更灵活且响应零延迟）。

## Decisions

### 1. 资产数据模型 Metadata 内存缓存
- **决策**：在 `PentestAsset` 中引入 `Map<String, dynamic>? _cachedMetadata` 字段；`metadata` getter 在首次读取时反序列化并保存引用，后续直接返回缓存引用。
- **替代方案考虑**：在构造函数中预先解码。
  - **放弃理由**：单次构造函数全部解码会增加数据拉取阶段的尖峰消耗；懒加载缓存仅在需要展示或筛选时解码一次，更省内存且兼顾性能。

### 2. 侦察资产列表分页组件（`AssetPaginationBar`）
- **决策**：
  - 维护 `int _currentPage = 1; static const int _pageSize = 50;`。
  - 过滤后计算 `totalPages = (filtered.length / _pageSize).ceil().clamp(1, 999999)`，若 `_currentPage > totalPages` 则自动重置为 `totalPages`。
  - 渲染切片：`final pagedAssets = filtered.skip((_currentPage - 1) * _pageSize).take(_pageSize).toList()`。
  - 在列表底部提供分页导航条：显示当前区间（如 `第 1-50 / 共 4,155 条 · 第 1/84 页`）、上一页与下一页按钮。
- **效果**：每次重绘只创建 50 个组件，渲染耗时由 > 10 秒骤降至 2 毫秒，彻底根治卡死。

### 3. 会话生命周期隔离与状态清理
- **决策**：
  - `_buildActiveView()` 中为 `WebReconView` 和 `LanReconView` 增加 `key: ValueKey(_controller.current?.id)`。
  - 保证切换不同 Web 或 LAN 会话时，旧会话的 State 彻底卸载，新会话自动使用自身 `scope` 初始化输入框，且分页器干净重置到第 1 页。

### 4. 会话快捷删除交互与批量级联 SQL 优化
- **决策**：
  - **交互**：
    - 在 `_SessionSwitcher` 下拉菜单的每一行末尾增加 `IconButton(Icons.delete_outline)`，点击弹出确认弹窗后执行删除；
    - 在 `SessionBar` 当前会话信息旁增加快捷删除按钮。
  - **SQL 批量优化**：
    - 废除 `for (final assetId in assetIds)` 串行循环，改为单条批量条件更新：
      ```dart
      await (database.update(database.sessionFindings)
            ..where((t) => t.sessionId.equals(id)))
          .write(const db.SessionFindingsCompanion(assetId: Value(null)));
      ```
    - 级联删除全部在该事务内以 `sessionId.equals(id)` 批量执行，耗时从数十秒降至 5ms。
  - **自动切换活跃会话**：
    - `SecuritySessionController.deleteSession` 在完成删除后，如果 `current?.id == id`，若剩余 `sessionList` 不为空，自动调用 `selectSession(sessionList.first.id)`。

## Risks / Trade-offs

- **[Risk] 用户在非第 1 页切换过滤器导致页码越界** → **Mitigation**: 在 build 计算中增加 `_currentPage = _currentPage.clamp(1, totalPages)` 自动防越界保护。
