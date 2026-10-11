## 1. BingSearchBackend Enhancements

- [x] 1.1 Implement aggregated endpoint failure reporting in `BingSearchBackend` so all endpoint errors are clearly surfaced
- [x] 1.2 Enhance HTTP request headers (Sec-Ch-Ua, Accept-Language, Accept) and query parameters (`setlang`, `cc`) for Bing endpoints to reduce anti-bot / redirect anomalies
- [x] 1.3 Add redirect-tolerant HTML parsing for Bing responses

## 2. DuckDuckGo and Fallback Backend Improvements

- [x] 2.1 Refactor `DuckDuckGoSearchBackend` to use resilient GET requests with browser headers
- [x] 2.2 Handle HTTP 202 / temporary response status codes with retry logic

## 3. WebSearchService Cooldown and Auto-Recovery

- [x] 3.1 Implement adaptive cooldown duration (shorter initial cooldown) in `WebSearchService`
- [x] 3.2 Implement auto-recovery probing: when all backends are in cooldown, automatically reset the primary backend's cooldown and attempt search instead of rejecting immediately

## 4. Verification and Testing

- [x] 4.1 Run unit and integration tests for `BingSearchBackend`, `DuckDuckGoSearchBackend`, and `WebSearchService`
- [x] 4.2 Verify in real network environment with and without proxy
