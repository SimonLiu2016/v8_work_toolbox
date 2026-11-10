## Why

在小说管理器“分类书库多页探索与AI智能去重采集”对话框中，用户反馈选择“飘天文学”后切换“主菜单/类型”时，搜索结果感觉没有按类型分类检索，部分分类没有对应上。
经排查，造成该问题的根因包括：
1. **Flutter 下拉组件数据流绑定缺陷**：`DropdownButtonFormField` 仅使用了 `initialValue` 而非受控的 `value` 属性，导致切换书源站点或动态重置分类键值时，UI 下拉框选中的视觉状态与实际底层发起的请求参数发生脱节。
2. **列表卡片伪分类标签误导**：飘天文学等站点的目录列表页 HTML 中不包含“分类”列，爬虫解析出的分类为空字符串，UI 列表项盲目回退并硬编码显示当前选中的分类名，在 UI 状态脱离或跨源展示时导致用户误以为所有条目都被错误归类。
3. **书源分类映射与路由缺失**：飘天文学主菜单第一项为“全部文章”（`/booksort/0/{page}.html`），但预置规则仅支持 `1~9`，且 `catalogUrl` 模板未能兼容空分类或全本分类等变体。

需要修复分类下拉框的受控双向绑定、规范分类标签展示，并完善飘天文学等源站的分类定义与路由兼容。

## What Changes

- **修复 `SiteCatalogDiscoveryDialog` 下拉框受控状态绑定**：
  - 将书源下拉与分类下拉的 `DropdownButtonFormField` 的 `initialValue` 改为完全受控的 `value` 属性绑定。
  - 在书源切换 `_onRuleChanged` 时，保证重选有效的分类 key，防止非法 key 导致的 UI 断言或状态脱离。
- **完善飘天文学等源站分类映射与路由解析**：
  - 在 `SiteScraperRuleService.defaultPiaotiaRule` 中增加 `'0': '全部文章'` 分类，并补全玄幻/武侠/都市等源站分类备注。
  - 在 `HttpRuleScraper.resolveCategoryUrl` 中优化 `{category}` 替换逻辑，当分类为 `0` 或空时，正确映射飘天文学的 `/booksort/0/{page}.html`（或 `/booksort0/0/{page}.html`）等兼容路由。
  - 自动更新 SQLite 中已存在的 `piaotia` 预置规则中的 `categoryMap`。
- **优化探索结果列表卡片的分类标签展示**：
  - 区分“条目自身携带分类”与“当前检索筛选条件”，当条目自身无分类列时，标注为 `源站分类: xxx` 或依据筛选条件呈现，避免产生“抓取到的书籍被错误打上单一标签”的认知冲突。

## Capabilities

### Modified Capabilities
- `novel-manager`: 增强分类小说库自动分页探索中的分类下拉绑定、全站/分类路由解析，以及分类元数据展示体验。

## Impact

- 受影响的代码模块：
  - `lib/tools/novel_manager/ui/site_catalog_discovery_dialog.dart`（UI 交互与状态绑定）
  - `lib/tools/novel_manager/services/site_scraper_rule_service.dart`（飘天文学预置规则与分类字典）
  - `lib/tools/novel_manager/services/http_rule_scraper.dart`（分类 URL 路由解析兼容）
  - `lib/tools/novel_manager/services/novel_database.dart`（预置规则分类字典同步机制）
- 不引入破坏性变更，完全向后兼容。
