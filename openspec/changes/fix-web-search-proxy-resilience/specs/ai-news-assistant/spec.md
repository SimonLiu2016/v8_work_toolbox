## ADDED Requirements

### Requirement: Resilient web search backend orchestration and proxy failover
The web retrieval system SHALL automatically adapt its search endpoint routing based on proxy status, provide cross-domain failover, and support secondary fallback search backends to ensure uninterrupted search capabilities across both proxy and direct-connection environments.

#### Scenario: Search with active proxy selects international endpoint
- **WHEN** user or scheduled task executes a web search and proxy routing is enabled for the AI assistant
- **THEN** the search backend prioritizes the international search endpoint (`www.bing.com`) to avoid regional TLS termination or 301 homepage redirects.

#### Scenario: Search with direct connection selects mainland endpoint
- **WHEN** user or scheduled task executes a web search without an active proxy
- **THEN** the search backend prioritizes the mainland search endpoint (`cn.bing.com`) for optimal direct connectivity.

#### Scenario: Primary domain failure triggers automatic alternate domain failover
- **WHEN** a search request to the preferred endpoint encounters a handshake error, connection reset, HTTP failure, or empty parsed results
- **THEN** the search backend immediately attempts the alternate endpoint (`cn.bing.com` <-> `www.bing.com`) before declaring the backend unhealthy.

#### Scenario: All primary engine endpoints fail falls back to secondary search backend
- **WHEN** the primary search backend (Bing) fails across all candidate endpoints
- **THEN** the orchestrator automatically degrades to the secondary zero-configuration search backend (DuckDuckGo Lite) without throwing a premature failure to the user.

#### Scenario: Search requests honor tool-specific proxy configuration
- **WHEN** web search requests are initiated
- **THEN** the underlying HTTP client is configured with the tool identifier (`ai-assistant`) so that proxy routing decisions respect per-tool proxy settings.
