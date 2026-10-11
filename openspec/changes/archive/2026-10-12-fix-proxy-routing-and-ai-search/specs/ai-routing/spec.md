## MODIFIED Requirements

### Requirement: Provider health state tracking
The routing engine SHALL maintain a per-provider health state cache that records the most recent success or failure timestamp and enforces a configurable cooldown window (default: 60 seconds) during which a failed provider is skipped without issuing a network request. The cache SHALL be cleared whenever network proxy settings or provider endpoints change.

#### Scenario: Provider fails and enters cooldown
- **WHEN** a request to a provider results in a network error, HTTP 4xx/5xx, or timeout
- **THEN** the provider's health state is updated to unhealthy with the current timestamp, and subsequent routing decisions skip this provider until the cooldown expires

#### Scenario: Provider recovers after cooldown
- **WHEN** a provider's cooldown window expires and a new request arrives for a slot where that provider is a candidate
- **THEN** the routing engine attempts the provider again; if the request succeeds, the provider's health state is reset to healthy

#### Scenario: Successful request resets health state
- **WHEN** a request to a provider succeeds (HTTP 200 with valid response)
- **THEN** the provider's health state is updated to healthy with the current timestamp, clearing any prior failure record

#### Scenario: Proxy change resets provider health cache
- **WHEN** the application's network proxy is enabled, disabled, or its host/port configuration is modified
- **THEN** the routing engine immediately purges the provider health state cache and reconnects using the updated network transport, allowing previously failing providers to be retried instantly under the new route.

## ADDED Requirements

### Requirement: Proxy bypass and direct routing for local and private endpoints
The network client and AI routing layer SHALL inspect destination endpoints against proxy bypass rules, ensuring loopback, private intranet (RFC 1918), and designated direct domestic hostnames or IP addresses connect directly without traversing foreign proxy nodes.

#### Scenario: Local and private IP endpoints bypass proxy
- **WHEN** an AI provider or API call targets `localhost`, `127.0.0.1`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, or an address specified in the bypass list
- **THEN** the HTTP connection connects directly (`DIRECT`), preventing 502 Bad Gateway or connection reset errors caused by outbound foreign proxy tunnels attempting reverse inbound connections.
