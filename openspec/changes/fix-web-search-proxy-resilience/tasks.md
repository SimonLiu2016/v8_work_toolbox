## 1. Bing 搜索后端自适应与主备容灾

- [x] 1.1 改造 `BingSearchBackend` 支持双端点（`www.bing.com` 国际 / `cn.bing.com` 国内），并根据代理状态自适应选择首选端点
- [x] 1.2 在 `BingSearchBackend` 中实现端点故障自动容灾切换（握手失败、网络错误、空结果时自动尝试备用端点）与连接重试
- [x] 1.3 确保网络客户端创建时传递 `toolId: 'ai-assistant'`，遵循工具级代理分流

## 2. 新增 DuckDuckGo Lite 搜索兜底后端

- [x] 2.1 实现 `DuckDuckGoSearchBackend`，支持 DuckDuckGo HTML Lite 查询与搜索结果提取
- [x] 2.2 在 `WebSearchService._searchChain` 编排链中接入 `DuckDuckGoSearchBackend` 作为二级自动兜底

## 3. 单元测试与端到端验证

- [x] 3.1 完善 `test/services/web_search_service_test.dart`，覆盖 Bing 端点自适应与 DuckDuckGo HTML 解析测试
- [x] 3.2 执行全量单元测试与应用集成验证，确认代理环境下真实搜索顺畅可用
