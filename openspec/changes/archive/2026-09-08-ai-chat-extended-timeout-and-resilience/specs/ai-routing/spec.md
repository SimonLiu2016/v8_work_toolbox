# ai-routing Specification Delta

## MODIFIED Requirements

### Requirement: Multi-candidate slot resolution
The routing engine SHALL resolve each capability slot (text / multimodal / tts / stt) by iterating through the slot's ordered candidate list in priority order, selecting the first candidate whose provider is currently marked healthy, with support for caller-specified execution timeouts to accommodate deep reasoning models.

#### Scenario: Primary candidate is healthy
- **WHEN** a business tool requests AI completion for the "text" slot and the highest-priority candidate's provider is healthy
- **THEN** the request is routed to that candidate's provider and model without attempting any other candidates

#### Scenario: Primary candidate is unhealthy, secondary available
- **WHEN** the highest-priority candidate's provider is marked unhealthy (within cooldown window) and a lower-priority candidate is healthy
- **THEN** the request is routed to the lower-priority candidate and a degradation event is recorded

#### Scenario: All candidates exhausted
- **WHEN** all candidates in a slot's ordered list are marked unhealthy or have failed during the current request cycle
- **THEN** the engine SHALL raise a `SlotUnavailableException` containing the slot name, the number of candidates attempted, and the last error from each candidate

#### Scenario: Chat completion with extended timeout
- **WHEN** a business tool or agent dialog issues a chat completion request to a slot with a configured or custom timeout (e.g. 90 seconds)
- **THEN** each candidate attempt is granted the specified duration, preventing premature abortion while reasoning models formulate thought chains and multi-paragraph analyses.

#### Scenario: Primary candidate times out after extended window
- **WHEN** the primary candidate fails to complete within the extended timeout window
- **THEN** the request fails over to the next configured candidate in priority order, recording the latency and timeout error in the routing trace.
