## Context

见 `proposal.md`。本地 SQLite 数据库文件位于 `AppPaths.novelDatabaseFile`（`~/Library/Application Support/V8WorkToolbox/novel_library/novel_manager.sqlite`）。`scraper_rules` 表在原数据库版本 2 中缺少 `category_map` 列，而 `SiteScraperRule.toMap()` 已开始输出该字段，导致在任何写表操作（如补齐系统免盾源或用户保存规则）时抛出 `no column named category_map` 异常，中断了规则加载过程。

## Goals / Non-Goals

**Goals:**
- SQLite 数据库版本自 `2` 升级至 `3`，建表与升级脚本均显式添加 `category_map TEXT`。
- 在 `NovelDatabase` 初始化与 `openDatabase` 时保证老版本 SQLite 表无损平滑 `ALTER TABLE` 升级。
- 在 `SiteScraperRule.toMap` 与入库逻辑中提供防崩溃防御（运行时自愈），即使面对未升级的特殊测试环境也不直接致命崩溃。
- 解耦 `SiteScraperRuleService.getRules()` 中自动同步默认源的操作，采用 try-catch 隔离，无论默认源注入成功与否，均保证数据库已有老书源安全加载并送达 UI。

**Non-Goals:**
- 不重写小说的正文存储结构（仍维持原子文件系统存储）。
- 不破坏现有用户已自定义的书源 ID、URL 或选择器。

## Decisions

### 1. 数据库版本由 2 跃迁至 3 并增补 `category_map`
- **决定**：在 `NovelDatabase` 中将 `version` 提升至 `3`，并在 `onUpgrade` 中加入：
  ```dart
  if (oldVersion < 3) {
    try {
      await db.execute('ALTER TABLE scraper_rules ADD COLUMN category_map TEXT');
    } catch (_) {}
  }
  ```
- **备选方案**：运行时动态执行 `PRAGMA table_info` 校验每列。缺点：开销较大且代码脆弱；版本号迁移是 SQLite 的标准最佳实践。

### 2. 数据库写入防御性自愈（Dynamic Column Filtering）
- **决定**：在 `insertOrUpdateRule` 中，先捕获一次潜在的缺列异常；若触发字段不存在错误，则自动剥离不存在的字段重试写入，并异步补齐 `ALTER TABLE`。
- **价值**：双重兜底，避免未来新增规则属性时再次因迁移未覆盖导致死锁。

### 3. `getRules()` 默认源注入隔离
- **决定**：`getRules()` 探测 `piaotia` 默认源并补充入库时，使用 `try { await _db.insertOrUpdateRule(defaultPiaotiaRule); } catch (e) { ... }` 隔离。无论写入是否成功，最终均返回当前已有的有效规则列表给 UI，UI 永不因后台补全失败而变成空列表。

## Risks / Trade-offs

- [Risk] 用户数据库可能处于 wal 锁占用状态 → SQLite 单连接并发通过 `sqflite` 内部队列管理，已配置 `PRAGMA foreign_keys = ON`，`onUpgrade` 会在同一事务上下文中安全执行。
- [Trade-off] 剥离列降级可能导致极少数极端情况下的字段暂时未存盘 → 伴随 `ALTER TABLE` 自动补齐，下次保存即完整落盘。
