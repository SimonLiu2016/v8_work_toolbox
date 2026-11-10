## Context

详见 `proposal.md`。当前 `HttpRuleScraper` 在抓取分类页面时，由于 `curl` 降级未启用严格失败标志，将 Cloudflare 403 Challenge 验证盾页面作为正常 HTML 返回，导致解析结果静默为空。同时分类 URL 路由硬编码、默认源站全面失效且缺乏反爬拦截错误识别，导致用户在多页检索时只看到空结果。

## Goals / Non-Goals

**Goals:**
- 建立严格的反爬盾防御识别：在 `_fetchHtml` 及解析层准确识别 Cloudflare Turnstile / 5s 盾，抛出显式 `AntiBotChallengeException`，杜绝将挑战拦截页面当做正常正文并伪装为空数据。
- 动态模板化分类 URL：支持在 `rule.catalogUrl` 中使用占位符（`{category}` / `{type}` / `{page}` / `{pageIndex}`），消除硬编码路由。
- 预置开箱即用的真实免盾书源：在预置规则与数据库初始化中加入真实可用、无需过盾的主流开放中文书源模板，保证用户检索立即可见真实数据。
- 完善 UI 异常与诊断交互：在 `SiteCatalogDiscoveryDialog` 中明确区分“网络错误”、“反爬防护阻断”与“解析为空”，提供重试及切换源站指引。

**Non-Goals:**
- 不在本期实现复杂的逆向破解 Cloudflare Turnstile 验证码（遇到强盾应当准确识别、快速失败并给用户明确反馈，而非死循环或假装成功）。

## Decisions

### D1: 统一反爬特征检测与显式异常 `AntiBotChallengeException`
- **方案**：新增 `AntiBotChallengeException`。在 `HttpRuleScraper._fetchHtml` 的所有出口（包括 `_client.get` 与 `Process.run('curl')`）：
  1. `curl` 调用必须增加 `--fail`（或检查 HTTP header 状态码）；
  2. 对返回的 HTML 文本进行特征扫描（`Just a moment...`、`cf-chl-widget`、`challenges.cloudflare.com`、`Attention Required! | Cloudflare` 等）；
  3. 一旦命中特征或收到 403 挑战响应，立即抛出 `AntiBotChallengeException(targetUrl, reason)`。
- **为什么**：彻底根除“curl exitCode 0 返回拦截页被上层当作成功 HTML”的根源漏洞。

### D2: 动态分类 URL 路由与智能兜底
- **方案**：
  在 `HttpRuleScraper.scrapeCategoryPage` 中计算目标 URL：
  ```dart
  String targetUrl;
  if (rule.catalogUrl.contains('{category}') || rule.catalogUrl.contains('{type}') || rule.catalogUrl.contains('{page}')) {
    targetUrl = rule.catalogUrl
        .replaceAll('{category}', categoryKey)
        .replaceAll('{type}', categoryKey)
        .replaceAll('{page}', pageIndex.toString())
        .replaceAll('{pageIndex}', pageIndex.toString());
  } else {
    // 兼容旧规则或未配置模板的站点
    final cleanBase = rule.baseUrl.replaceAll(RegExp(r'/+$'), '');
    targetUrl = '$cleanBase/class/${categoryKey}_$pageIndex/';
  }
  ```
- **为什么**：让分类检索真正支持任意遵循标准 URL 模式的站点，避免 szlajc 路径绑死全系统。

### D3: 预置开箱可用的免盾标准源
- **方案**：在 `SiteScraperRuleService._initDefaultRules` 中，调整默认源：
  1. 修复/更新现存规则（标注 szlajc 为 `[CF强盾/不可直连]`）；
  2. 增加 1 个以上免盾、免 Cloudflare 拦截且结构稳定的公共小说源（如主流笔趣阁/开放阅读镜像站），配置正确的 `catalogUrl`、`catalogSelector` 及章节选择器；
  3. 在 `NovelDatabase` 启动升级逻辑中，确保新默认规则自动就位且不覆盖用户的自定义修改。

### D4: 探索弹窗诊断体验与容错反馈
- **方案**：
  在 `SiteCatalogDiscoveryDialog` 中：
  1. 若 `exploreCategoryPages` 抛出 `AntiBotChallengeException`，UI 展示醒目的反爬盾警示图标，提示“该站点开启了 Cloudflare 防火墙强校验，普通网络无法直连抓取，建议切换至其他免盾书源”；
  2. 若扫描完毕后条数为 0，展示“未从该源站匹配到任何作品（可能是分类页面结构变更或选择器不匹配）”，而非单纯的“暂无小说请点击检索”。

## Risks / Trade-offs

- **[开放源站时效性风险] → [缓解]**：公共小说站域名或 DOM 结构可能随时间变更。缓解：预置规范 CSS 选择器，且在站点管理页面保留让用户自主修改 URL 模板与选择器的能力。
- **[数据库已有规则数据不一致] → [缓解]**：已有 SQLite 数据库中可能存在旧的空 `catalog_url`。缓解：在读取规则和执行探索时均做安全兜底插值，数据库升级时对默认 id 做平滑更新。

## Migration Plan

1. 代码更新后无破坏性数据库变更（已有字段平滑更新）。
2. 构建并热部署应用后，旧数据库的默认规则将自动补充可用源。
