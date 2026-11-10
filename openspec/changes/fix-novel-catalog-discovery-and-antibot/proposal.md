## Why

在小说管理器的「分类书库多页探索与 AI 智能去重采集」功能中，用户选择站点与分类点击「多页检索」后，页面没有报任何错误，但采集列表一直为空（提示“暂无小说，请点击上方“多页检索”开始扫描”），导致无法发现并采集任何小说。

核心原因在于：
1. `_fetchHtml` 在发生 HTTP 403 错误（如 Cloudflare Turnstile 挑战盾拦截）时降级调用 `curl`，但未启用 `--fail` 且未校验 Cloudflare 挑战页面标志，直接将 `<title>Just a moment...</title>` 人机验证 HTML 作为正常响应返回；
2. `scrapeCategoryPage` 使用 CSS 选择器无法从挑战页面匹配到任何书籍节点，返回 0 部作品且无异常抛出，导致 UI 将反爬拦截误判为“源站分类下无小说”并静默置空；
3. `exploreCategoryPages` 硬编码写死了 `/class/{type}_{page}/` 路径，完全忽略规则中配置的 `catalogUrl`；且在多页探索链路中完全遗漏了 `AntiBotBypassScraper` 的穿透调用；
4. 预置的默认规则（如 `szlajc.com` 已开启 Cloudflare 全站强盾且云端 IP 被封禁，`example-novel.com` 为假域名）在当前网络环境下无法直接抓取。

## What Changes

- **严格的反爬拦截与错误识别**：
  - 在 `HttpRuleScraper._fetchHtml` 中，对 HTTP 状态码（>=400）及响应正文进行严格防御性校验；
  - 拦截并识别 Cloudflare Turnstile 页面标志（`Just a moment...`、`cf-chl-widget`、`challenges.cloudflare.com`），禁止将人机验证页面当成正文返回；
  - 遇到反爬拦截或页面解析结果为空且页面包含异常标识时，抛出显式的 `AntiBotChallengeException` 或业务异常，杜绝“拦截被伪装为空内容”。
- **动态分类 URL 路由模板解析**：
  - `HttpRuleScraper.scrapeCategoryPage` 不再写死 `/class/${categoryKey}_$pageIndex/`；
  - 优先使用 `rule.catalogUrl` 中的模板变量（支持 `{category}`、`{type}`、`{page}`、`{pageIndex}` 等占位符），未配置模板时根据站点结构智能回退。
- **多页探索接入反爬穿透与状态展示**：
  - 在 `NovelScraperCoordinator.exploreCategoryPages` 中，当轻量规则抓取触发反爬异常且 `rule.enableBypass == true` 时，支持调用穿透管道；
  - 在 `SiteCatalogDiscoveryDialog` 中完善状态与错误提示：当抓取失败或返回 0 条时，给出明确诊断（例如：源站开启强反爬防护、网络超时或选择器未匹配），并提供一键重试与规则配置入口。
- **预置真实、免盾的高可用小说源规则**：
  - 更新默认内置站点规则，提供免 Cloudflare 强盾的开放真实书源（如主流免盾开放小说源模板），并在数据库升级或初始化时同步补充，确保用户开箱即可正常多页检索出作品。

## Capabilities

### New Capabilities
（无新增 capability，本变更为既有 `novel-manager` 能力缺陷修复与健壮性增强。）

### Modified Capabilities
- `novel-manager`: 增强「分类小说库自动分页探索」的反爬挑战识别、动态 URL 模板支持、错误诊断透传与预置真实免盾源规则。

## Impact

- **Affected Code**:
  - `lib/tools/novel_manager/services/http_rule_scraper.dart`（修复 `_fetchHtml` 错误吞噬与 Cloudflare 伪成功检测，实现动态 URL 模板）
  - `lib/tools/novel_manager/services/novel_scraper_coordinator.dart`（在 `exploreCategoryPages` 增加穿透调用与异常向上传播）
  - `lib/tools/novel_manager/services/site_scraper_rule_service.dart` 与 `novel_database.dart`（补充/修正可用书源规则，处理旧数据缺省字段）
  - `lib/tools/novel_manager/ui/site_catalog_discovery_dialog.dart`（增强 0 结果诊断、反爬拦截状态提示及重试体验）
  - `test/` 相关测试用例
- **Dependencies & APIs**: 无新增第三方依赖，复用既有 `http`、`html`、`McpService` 等。
