## MODIFIED Requirements

### Requirement: Model discovery and capability slots
The application SHALL allow discovering available models via authentic provider API requests or manual entry, and assigning models to global capability slots (Text, Multimodal, TTS, STT, Image, Video). Each slot SHALL support an ordered list of provider-model candidates instead of a single binding, with user-controllable priority ordering.

For the Image and Video slots, each candidate model SHALL carry an optional capability declaration describing its supported generation modes, durations, resolutions, aspect ratios, reference-image limits, first/last frame support, and native audio support. A model without a declaration SHALL resolve to a conservative default derived from its protocol type, and consumers SHALL be able to distinguish a declared capability from a defaulted one.

#### Scenario: Automatic model discovery
- **WHEN** user clicks "Detect Models" for an active provider
- **THEN** the system queries the provider's models endpoint via real HTTP request and populates returned model identifiers, or raises an informative error if the credentials/network fail.

#### Scenario: Adding a candidate to a slot
- **WHEN** user selects a provider and model and adds them to a slot's candidate list
- **THEN** the new candidate is appended at the lowest priority position, and the slot's ordered candidate list is persisted to `ai_config.json`

#### Scenario: Reordering slot candidates
- **WHEN** user drags a candidate to a new position within a slot's candidate list
- **THEN** the priority order is updated accordingly and is persisted, and subsequent AI routing uses the new order

#### Scenario: Removing a candidate from a slot
- **WHEN** user removes a candidate from a slot's candidate list
- **THEN** the candidate is removed, remaining candidates retain their relative order, and the change is persisted

#### Scenario: Routing requests through capability slot
- **WHEN** a business tool requests text completion without specifying an explicit provider
- **THEN** the system resolves the provider and model via the slot's ordered candidate list and the auto-healing routing engine

#### Scenario: Backward-compatible loading of legacy single-binding format
- **WHEN** the application loads an `ai_config.json` containing the legacy `defaultSlots` format with single `{providerId, model}` entries
- **THEN** each legacy binding is automatically migrated to a single-element candidate list, and the config is re-saved in the new format without data loss

#### Scenario: Image or Video candidate without declaration resolves to conservative default
- **WHEN** the application loads an `ai_config.json` whose Video slot candidate has no capability declaration
- **THEN** the candidate resolves to the conservative default for its protocol type, and consumers can tell it is a default rather than a declared capability
