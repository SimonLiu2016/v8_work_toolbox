## 1. 源站规则与路由解析优化

- [x] 1.1 在 `SiteScraperRuleService.defaultPiaotiaRule` 中补充 `'0': '全部文章 (全站综合)'` 分类并优化分类名称提示
- [x] 1.2 在 `HttpRuleScraper.resolveCategoryUrl` 与 `AntiBotBypassScraper` 中支持针对飘天文学等站点的 `categoryKey == '0'` 自适应占位符映射
- [x] 1.3 在 `SiteScraperRuleService.ensureDefaultRules()` 中增加已有预置规则分类字典的自愈升级逻辑

## 2. UI 交互与受控状态绑定修复

- [x] 2.1 修复 `SiteCatalogDiscoveryDialog` 中书源选择与分类选择的 `DropdownButtonFormField` 为受控 `value` 绑定，并在重绘前做好键值安全防守
- [x] 2.2 优化 `_onRuleChanged` 与分类切换时的联动逻辑，确保 UI 显示与内部发起的实际扫描参数严格一致
- [x] 2.3 优化探索结果卡片的分类标签展示逻辑，清晰区分条目本身自带分类与当前检索分类

## 3. 验证与本地部署

- [x] 3.1 编写/更新规则解析与分类映射单元测试，确保 `resolveCategoryUrl` 与分类同步逻辑准确无误
- [x] 3.2 运行测试套件验证回归
- [x] 3.3 执行 `./scripts/deploy_local.sh` 编译部署并验证本机应用
