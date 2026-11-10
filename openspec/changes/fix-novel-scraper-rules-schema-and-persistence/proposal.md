## Why

在小说管理器中，之前保存的书源规则与新增书源规则在应用启动及界面打开后不可见，且新建或保存书源时报错失效。排查发现 `SiteScraperRule` 增加了分类映射字段 `category_map`，但底层 SQLite 表 `scraper_rules` 缺少对应的列定义及版本升级迁移，导致任何包含分类字典的规则持久化时均因 `no column named category_map` 崩溃阻断，使得书源列表无法加载并展示为空。本变更旨在通过数据库平滑升级与模型持久化兼容自愈，彻底恢复既有书源及新增书源的持久化与正常呈现。

## What Changes

- **数据库版本迁移与 Schema 修复**：将 SQLite 数据库版本自 `2` 升级至 `3`，并在建表 `_createTables` 与增量升级 `onUpgrade` 中补全 `category_map TEXT` 列定义。
- **持久化写入兼容自愈**：在 `SiteScraperRule.toMap()` 与 `NovelDatabase.insertOrUpdateRule` 层面加入防御自愈（在 SQLite 未迁移完成或字段缺失时平滑兼容），避免未知或新增列导致写操作异常终止。
- **书源读取与初始化的容错解耦**：优化 `SiteScraperRuleService.getRules()`，在补全默认推荐免盾源（如 `piaotia`）时添加独立异常保护，确保既有老书源（如 `szlajc`、自定义规则等）始终安全正常加载返回给 UI。
- **界面即时刷新与数据恢复**：确保书源管理弹窗及书库探索弹窗在打开及保存规则后，能稳定获取并展示全部书源。

## Capabilities

### Modified Capabilities

- `novel-manager`: 修复书源站点规则的数据库 Schema 完整性、增量自动迁移以及分类映射持久化自愈能力，确保用户保存的书源站点与系统推荐源无损读取和保存。

## Impact

- 受影响文件：`lib/tools/novel_manager/services/novel_database.dart`、`lib/tools/novel_manager/services/site_scraper_rule_service.dart`、`lib/tools/novel_manager/models/novel_models.dart`。
- 本地既有数据无损继承，用户既有小说条目与历史规则完整保留。
