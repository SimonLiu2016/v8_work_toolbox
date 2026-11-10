## 1. 数据库升级与 Schema 列补齐

- [x] 1.1 在 `NovelDatabase._initDatabase` 中将 SQLite 版本升级至 `version: 3`
- [x] 1.2 在 `NovelDatabase._createTables` 中为 `scraper_rules` 表新增 `category_map TEXT` 列定义
- [x] 1.3 在 `NovelDatabase.onUpgrade` 中增加版本 3 迁移逻辑：对低版本数据库自动执行 `ALTER TABLE scraper_rules ADD COLUMN category_map TEXT`

## 2. 数据库写入自愈与异常隔离

- [x] 2.1 在 `NovelDatabase.insertOrUpdateRule` 中加入防御性异常捕获与缺列自愈重试机制
- [x] 2.2 在 `SiteScraperRuleService.getRules()` 中为默认源补全逻辑添加 try-catch 隔离，确保即使写入异常也能平滑回退返回现有数据库规则

## 3. 测试验证与本地打包部署

- [x] 3.1 编写单元测试验证 `NovelDatabase` 从版本 2 平滑升级到版本 3 并正确读写 `category_map`
- [x] 3.2 运行所有关联测试，验证老书源加载与新书源保存无异常
- [x] 3.3 执行 `./scripts/deploy_local.sh` 编译并热部署到本地应用，验证书源在 UI 中完整恢复
