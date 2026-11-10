## Context

在小说管理器中，多页探索功能允许用户选择任意支持的书源站点（如预置免盾优质源“飘天文学”），并按站点配置的分类目录（如 1=玄幻魔法、2=武侠修真、3=都市言情等）批量扫描全站作品。
但在实际使用中，Flutter 的 UI 表单状态未建立真正的受控绑定，源站的分类定义缺乏“全部文章”的选项，且源站列表项自身缺少分类字段导致卡片标签展示引起用户误解。

详见 `proposal.md` 与 `specs/novel-manager/spec.md`。

## Goals / Non-Goals

**Goals:**
- 将 `SiteCatalogDiscoveryDialog` 中的规则与分类下拉框改为严格受控的 `value` 绑定，彻底修复书源切换与分类重置时的状态不同步问题。
- 在飘天文学预置规则与数据库自愈更新逻辑中加入 `'0': '全部文章 (全站综合)'` 分类，并增加分类特征备注。
- 完善 `HttpRuleScraper.resolveCategoryUrl` 与穿透采集器的路由映射，支持空分类或 `'0'` 分类自适应映射至 `/booksort/0/{page}.html`。
- 优化结果列表卡片分类标签的渲染逻辑，客观展示分类信息。

**Non-Goals:**
- 不重构整体爬虫解析流水线或 AI 去重引擎底层算法。
- 不强制对每个条目发起详情页反向回查分类（避免单次多页探索产生数千次额外的详情页 HTTP 开销）。

## Decisions

### 1. DropdownButtonFormField 完全受控化并设置联动保护
- **决策**：使用 `value: _selectedRule` 与 `value: _selectedCategoryKey` 替换现有的 `initialValue`。
- **原因**：Flutter 的 `DropdownButtonFormField` 若仅传 `initialValue`，当外部执行 `setState` 更改绑定的值时，其内部 `FormFieldState` 不会刷新。受控模式下，每次外部状态变更都能即时反映在 UI 上。
- **保护机制**：在 `_onRuleChanged` 或分类列表重算时，若发现旧的 `_selectedCategoryKey` 不存在于新的 `_currentCategoryMap` 中，强制取新 map 的 `keys.first`，并在构建 items 列表前校验 `value` 合法性，防止因 `value not found in items` 引发 Flutter 断言崩溃。

### 2. 飘天文学预置规则与 URL 自适应解析
- **决策**：
  1. 在 `SiteScraperRuleService.defaultPiaotiaRule` 的 `categoryMap` 中增加 `'0': '全部文章 (全站综合)'`，并优化其他分类的名称。
  2. 在 `HttpRuleScraper.resolveCategoryUrl` 与 `AntiBotBypassScraper` 中，若规则包含 `booksort{category}` 且 `categoryKey == '0'`，将 `{category}` 替换为空字符串（即转换为 `/booksort/0/{page}.html`）；若 `categoryKey` 为非 0 数字，则正常替换为 `1` ~ `9`。
- **原因**：飘天文学源站主菜单的第一项就是 `/booksort/0/1.html`，既满足用户纵览全站最新收录的需求，又与源站主菜单保持 100% 一致。

### 3. SQLite 中已有飘天规则的平滑升级
- **决策**：在 `SiteScraperRuleService.ensureDefaultRules()` 中，比对现有 `piaotia` 规则的 `categoryMap`，若缺少 `'0'` 或版本较旧，自动用最新的 `defaultPiaotiaRule.categoryMap` 进行局部更新。
- **原因**：已存在本地数据库的旧安装实例不会重新跑建表逻辑，通过服务启动时的轻量自愈比对，老用户无需手动重置数据库即可拥有完整的全部分类。

### 4. 卡片分类标签区分“源站条目分类”与“当前筛选分类”
- **决策**：若爬虫未从源站列表行解析出单独的分类字段（如飘天文学），卡片标签标记为 `检索分类: xxx` 或纯净分类名，并在搜索状态栏与提示中清楚标明当前正在扫描的分类，避免用户产生“AI 或系统把书分类打错”的误解。

## Risks / Trade-offs

- **[Risk] DropdownButtonFormField value 抛出断言错误** → **[Mitigation]** 在 build 方法前执行 `final activeKey = _currentCategoryMap.containsKey(_selectedCategoryKey) ? _selectedCategoryKey : _currentCategoryMap.keys.firstOrNull;`，保证传给 `value` 的值必然在 `items` 中。
- **[Risk] 旧版 SQLite 规则覆盖用户自定义修改** → **[Mitigation]** 仅对 ID 为 `piaotia` 且属于系统默认免盾源的特定项检查 `categoryMap` 完整性，不影响用户自定义添加的其他站点。
