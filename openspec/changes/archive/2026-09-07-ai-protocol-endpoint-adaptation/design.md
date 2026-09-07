## Context

See `proposal.md` for motivation. In the current implementation, `AiService._chatAnthropic` hardcodes the messages endpoint to `$baseUrl/v1/messages` with only `x-api-key`, and `_chatOpenAi` expects `$baseUrl` to explicitly include `/v1`. However, modern multi-protocol gateways (such as Xiaomi MiMo, OneAPI, NewAPI, Cloudflare) mount Anthropic APIs under `/anthropic/v1/messages` and expect `api-key` headers.

## Goals / Non-Goals

**Goals:**
- Automatically adapt and route Anthropic requests to working endpoints (`/anthropic/v1/messages`, `/v1/messages`, `/messages`) without requiring manual URL surgery from users.
- Cache the resolved working endpoint per provider in memory to ensure zero overhead on subsequent requests.
- Inject dual authentication headers (`x-api-key` + `api-key` for Anthropic; `Authorization` + `api-key` for OpenAI) to be compatible with diverse gateway standards.
- Ensure OpenAI Base URL normalization so omitting `/v1` does not cause 404.
- Upgrade `testConnection()` to a two-phase check: model enumeration + real chat ping, preventing false-positive configuration passes.

**Non-Goals:**
- Supporting custom user-defined regex route rewrite rules.
- Modifying Google Gemini protocol (Gemini uses standard Google AI studio endpoints).
- Changing data models or persisted JSON schema in `ai_config.json`.

## Decisions

### Decision 1: In-memory resolved endpoint cache with fallback probing

**Choice**: Maintain a `Map<String, String> _resolvedChatEndpoint` in `AiService` (keyed by `provider.id`).
- When a provider is invoked for the first time, check candidate endpoints:
  - For Anthropic:
    1. If `baseUrl` already contains `/anthropic`, use standard normalization.
    2. Otherwise, candidates: `['$base/anthropic/v1/messages', '$base/v1/messages', '$base/messages']`.
  - On 404, immediately try the next candidate endpoint.
  - On 200, cache the successful endpoint path in `_resolvedChatEndpoint[provider.id]`.
- All subsequent calls for that provider use the cached endpoint directly (0ms probing latency).

**Rationale**: Transparent to the user. Whether they enter `https://token-plan-sgp.xiaomimimo.com` or `https://api.anthropic.com`, the software automatically hits the right endpoint on the first attempt and remembers it.

### Decision 2: Dual authentication headers injection

**Choice**:
- Anthropic headers:
  ```dart
  'anthropic-version': '2023-06-01',
  'x-api-key': apiKey,
  'api-key': apiKey,
  ```
- OpenAI headers:
  ```dart
  'Authorization': 'Bearer $apiKey',
  'api-key': apiKey,
  ```

**Rationale**: HTTP headers are case-insensitive and can coexist without conflict. Proxies that strictly demand `api-key` (e.g. Xiaomi MiMo, Azure OpenAI) or standard `x-api-key` (official Anthropic) both accept the request without negotiation roundtrips.

### Decision 3: Two-phase connection validation (Discover + Ping)

**Choice**: `testConnection(provider)` performs two steps:
1. `discoverModels(provider)`: fetches model list.
2. `ping(provider, model)`: dispatches a lightweight test prompt (`"ping"`, `max_tokens: 1`) to the chat endpoint using the resolved candidate path.
If step 2 fails (e.g., 404 or auth rejection), `testConnection()` throws a descriptive error with details instead of displaying false-positive success.

**Rationale**: Fixes the exact issue where model discovery succeeds (because `/v1/models` exists) but chat fails (because `/v1/messages` returned 404).

## Risks / Trade-offs

- **First-call probe latency on 404** → Probing candidate endpoints on the very first call adds ~100-200ms only if the primary path is 404. Once resolved, it is cached in memory for all subsequent requests.
- **Header compatibility** → Neither standard Anthropic nor OpenAI gateways reject extra unrecognized headers (`api-key`), making dual header injection safe.

## Migration Plan

- Backward-compatible; no config schema change required. Existing saved providers immediately benefit from adaptive routing.
