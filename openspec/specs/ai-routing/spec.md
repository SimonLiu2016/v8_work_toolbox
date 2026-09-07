# ai-routing Specification

## Purpose
Provides the runtime routing engine that resolves AI capability slot requests to healthy provider candidates, automatically falling back through an ordered candidate chain when the preferred provider is unavailable, and reporting transparent routing decisions to callers.
## Requirements
### Requirement: Multi-candidate slot resolution
The routing engine SHALL resolve each capability slot (text / multimodal / tts / stt) by iterating through the slot's ordered candidate list in priority order, selecting the first candidate whose provider is currently marked healthy.

#### Scenario: Primary candidate is healthy
- **WHEN** a business tool requests AI completion for the "text" slot and the highest-priority candidate's provider is healthy
- **THEN** the request is routed to that candidate's provider and model without attempting any other candidates

#### Scenario: Primary candidate is unhealthy, secondary available
- **WHEN** the highest-priority candidate's provider is marked unhealthy (within cooldown window) and a lower-priority candidate is healthy
- **THEN** the request is routed to the lower-priority candidate and a degradation event is recorded

#### Scenario: All candidates exhausted
- **WHEN** all candidates in a slot's ordered list are marked unhealthy or have failed during the current request cycle
- **THEN** the engine SHALL raise a `SlotUnavailableException` containing the slot name, the number of candidates attempted, and the last error from each candidate

### Requirement: Provider health state tracking
The routing engine SHALL maintain a per-provider health state cache that records the most recent success or failure timestamp and enforces a configurable cooldown window (default: 60 seconds) during which a failed provider is skipped without issuing a network request.

#### Scenario: Provider fails and enters cooldown
- **WHEN** a request to a provider results in a network error, HTTP 4xx/5xx, or timeout
- **THEN** the provider's health state is updated to unhealthy with the current timestamp, and subsequent routing decisions skip this provider until the cooldown expires

#### Scenario: Provider recovers after cooldown
- **WHEN** a provider's cooldown window expires and a new request arrives for a slot where that provider is a candidate
- **THEN** the routing engine attempts the provider again; if the request succeeds, the provider's health state is reset to healthy

#### Scenario: Successful request resets health state
- **WHEN** a request to a provider succeeds (HTTP 200 with valid response)
- **THEN** the provider's health state is updated to healthy with the current timestamp, clearing any prior failure record

### Requirement: Automatic failover with retry chain
The routing engine SHALL attempt each candidate in priority order during a single `chat()` invocation, advancing to the next candidate only upon transport-level or API-level failure, and SHALL NOT retry the same candidate within a single invocation.

#### Scenario: Sequential failover across three candidates
- **WHEN** a slot has candidates [A, B, C] and candidate A times out and candidate B returns HTTP 401
- **THEN** the engine attempts C; if C succeeds, the response is returned with the routing trace showing A→B→C

#### Scenario: No double-retry within a single call
- **WHEN** candidate A fails during a `chat()` invocation and the engine advances past A
- **THEN** candidate A is NOT retried again within the same invocation, even if its cooldown has not yet started

### Requirement: Routing decision transparency
Each `chat()` invocation SHALL return a structured result containing the response text, the provider ID and model name that actually served the request, and an ordered list of routing attempts (each with provider ID, outcome, and latency).

#### Scenario: Successful direct route
- **WHEN** a request is served by the primary candidate without degradation
- **THEN** the result includes `usedProviderId`, `usedModel`, and a single-entry routing trace with outcome "success"

#### Scenario: Degraded route with trace
- **WHEN** the primary candidate fails and the request is served by a fallback candidate
- **THEN** the result includes the fallback's provider ID and model, and the routing trace shows the failed primary attempt (with error) followed by the successful fallback attempt

### Requirement: Structured slot unavailability error
When a slot has zero candidates or all candidates fail, the system SHALL raise a `SlotUnavailableException` that includes the slot name, the count of configured candidates, and a per-candidate error summary, enabling business tools to display actionable guidance.

#### Scenario: Empty slot with no candidates
- **WHEN** a business tool requests the "tts" slot and no candidates are configured for that slot
- **THEN** a `SlotUnavailableException` is raised with zero candidate count and a message indicating no providers are bound to the slot

#### Scenario: All candidates failed
- **WHEN** a slot has 2 candidates and both fail with distinct errors (e.g., timeout and invalid key)
- **THEN** a `SlotUnavailableException` is raised listing both candidates with their respective error summaries

