## 1. 反爬拦截检测与防御修复

- [x] 1.1 在 `http_rule_scraper.dart` 中定义 `AntiBotChallengeException` 异常类，封装目标 URL 与拦截特征信息
- [x] 1.2 修复 `HttpRuleScraper._fetchHtml` 的 curl 降级与响应解析：增加 `--fail` 防御，并在返回前严格扫描 Cloudflare Turnstile / 5s 盾特征，命中时严禁返回正文，直接抛出 `AntiBotChallengeException`
- [x] 1.3 `HttpRuleScraper.scrapeCategoryPage` 确保反爬挑战异常与网络异常向上传播，杜绝静默返回 0 条作品

## 2. 动态分类 URL 路由模板与参数插值

- [x] 2.1 在 `HttpRuleScraper.scrapeCategoryPage` 中支持 `rule.catalogUrl` 动态模板插值（支持 `{category}`、`{type}`、`{page}`、`{pageIndex}` 等占位符）
- [x] 2.2 为无占位符或未配置 `catalogUrl` 的规则提供向后兼容的安全路由兜底

## 3. 默认书源规则库与数据库初始化升级

- [x] 3.1 在 `SiteScraperRuleService._initDefaultRules` 中更新规则，标注 `szlajc` 为 `[CF强盾]` 并补齐有效模板
- [x] 3.2 预置免盾、可直接访问的主流开放小说源规则模板（配置真实可用的 `catalogUrl`、`catalogSelector` 及正文/章节选择器）
- [x] 3.3 在 `NovelDatabase` 初始化或升级逻辑中，确保新默认规则自动就位且不覆盖用户的自定义规则

## 4. 探索界面（UI）诊断交互与错误引导

- [x] 4.1 在 `SiteCatalogDiscoveryDialog` 中捕获 `AntiBotChallengeException`，展示醒目的反爬盾警示与切换可用书源引导
- [x] 4.2 优化 0 结果时的状态反馈：区分“未开始扫描”、“反爬被阻断”与“解析为空（可能选择器失效）”，提供重试及编辑规则入口

## 5. 单元测试与部署验证

- [x] 5.1 单元测试：验证 `_fetchHtml` 遇到 Cloudflare Turnstile 挑战页面时准确抛出 `AntiBotChallengeException`
- [x] 5.2 单元测试：验证 `scrapeCategoryPage` 的动态 URL 模板插值与缺省安全回退
- [x] 5.3 单元测试：验证免盾源规则能够正常解析作品条目与分页信息
- [x] 5.4 执行 `./scripts/deploy_local.sh` 进行 Release 构建、签名并热替换本机应用进行功能验证
