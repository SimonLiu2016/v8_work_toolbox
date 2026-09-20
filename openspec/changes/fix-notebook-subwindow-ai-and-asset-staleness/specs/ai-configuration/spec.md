# ai-configuration Delta

## MODIFIED Requirements

### Requirement: Model discovery and capability slots
The application SHALL allow discovering available models via authentic provider API requests or manual entry, and assigning models to global capability slots (Text, Multimodal, TTS, STT). Each slot SHALL support an ordered list of provider-model candidates instead of a single binding, with user-controllable priority ordering. The configuration store backing these slots SHALL be initialized in every window process that consumes AI capabilities, so slot bindings resolve identically regardless of which window issues the request. Slot unavailability errors SHALL distinguish "configuration storage was not initialized in this process" from "no candidate is bound to this slot", so the two conditions are not conflated in diagnostics.

#### Scenario: Automatic model discovery
- **WHEN** user clicks "Detect Models" for an active provider
- **THEN** the system queries the provider's models endpoint via real HTTP request and populates returned model identifiers, or raises an informative error if the credentials/network fail.

#### Scenario: Adding a candidate to a slot
- **WHEN** user selects a provider and model and adds them to a slot's candidate list
- **THEN** the new candidate is appended at the lowest priority position, and the slot's ordered candidate list is persisted to `ai_config.json`

#### Scenario: Reordering slot candidates
- **WHEN** user drags a candidate to a new position within a slot's candidate list
- **THEN** the priority order is updated accordingly and persisted, and subsequent AI routing uses the new order

#### Scenario: Removing a candidate from a slot
- **WHEN** user removes a candidate from a slot's candidate list
- **THEN** the candidate is removed, remaining candidates retain their relative order, and the change is persisted

#### Scenario: Routing requests through capability slot
- **WHEN** a business tool requests text completion without specifying an explicit provider
- **THEN** the system resolves the provider and model via the slot's ordered candidate list and the auto-healing routing engine

#### Scenario: Backward-compatible loading of legacy single-binding format
- **WHEN** the application loads an `ai_config.json` containing the legacy `defaultSlots` format with single `{providerId, model}` entries
- **THEN** each legacy binding is automatically migrated to a single-element candidate list, and the config is re-saved in the new format without data loss

#### Scenario: Slot resolution from a non-main window process
- **WHEN** a window process other than the main window (e.g. the notebook sub-window) requests an AI capability by slot name
- **THEN** the slot bindings resolve to the same candidates as in the main window
- **AND** the request is routed to a bound candidate instead of failing with an empty-candidate error.

#### Scenario: Configuration storage unreadable is not conflated with unbound slot
- **WHEN** the configuration file cannot be read or parsed in this process
- **THEN** the failure is reported as a configuration-load failure with the underlying cause
- **AND** it is not silently replaced by an empty default that makes the user believe no candidate is bound.
