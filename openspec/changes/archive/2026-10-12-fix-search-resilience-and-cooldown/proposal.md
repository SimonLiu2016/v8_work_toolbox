## Why

In `WebSearchService`, web retrieval queries currently fail and enter cooldown due to two combined issues:
1. `BingSearchBackend` loops over endpoints (`www.bing.com` and `cn.bing.com`), but upon failure it overwrites `lastError` with the final endpoint's error (`cn.bing.com 结果页结构变更或发生重定向`), obscuring the root failure on `www.bing.com`. Additionally, `cn.bing.com` redirects (301) to the international Bing root in overseas proxy environments without returning `b_algo` result blocks.
2. `DuckDuckGoSearchBackend` receives HTTP 202 on certain proxy exit nodes, causing it to fail immediately as a fallback.
3. Once both Bing and DuckDuckGo fail, `WebSearchService` marks all backends unhealthy for a fixed 60-second cooldown period, preventing immediate user retries and locking up web search.

We need resilient search backend routing, aggregated diagnostic error reporting across endpoints, robust HTTP request headers/fallbacks, and smart cooldown backoff with forced fallback probing.

## What Changes

- **Aggregated Error Reporting in Bing Backend**: Collect and report errors across all candidate endpoints (`www.bing.com`, `cn.bing.com`) instead of shadowing earlier errors with the last attempt.
- **Enhanced Request Emulation & Redirect Handling**: Provide realistic browser headers and parameters (`setlang=zh-Hans`, proper User-Agent, Accept headers) to prevent anti-bot blocks and handle redirects cleanly.
- **DuckDuckGo Backend Resilience**: Support GET requests and handle HTTP 202 / intermediate response codes with retries.
- **Adaptive Cooldown & Fallback Policy in WebSearchService**: Instead of locking out all backends immediately for 60 seconds, use progressive cooldown, and when all backends are in cooldown, allow forced pass-through or auto-recovery probe for user queries.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `ai-news-assistant`: Enhance search backend resilience, multi-endpoint diagnostic transparency, and adaptive cooldown recovery for interactive web retrieval.

## Impact

- `lib/features/ai_assistant/services/web_search_service.dart`: Cooldown management, health checks, and fallback ordering.
- `lib/features/ai_assistant/services/search_backends/bing_search_backend.dart`: Candidate endpoint error aggregation, request headers, and redirect handling.
- `lib/features/ai_assistant/services/search_backends/duckduckgo_search_backend.dart`: Request headers and HTTP 202 handling.
- Tests covering `WebSearchService` and search backends.
