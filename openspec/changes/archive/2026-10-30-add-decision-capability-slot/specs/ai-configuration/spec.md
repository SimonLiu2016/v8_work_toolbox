## MODIFIED Requirements

### Requirement: Model discovery and capability slots
The application SHALL allow discovering available models via authentic provider API requests or manual entry, and assigning models to global capability slots (Text, Multimodal, TTS, STT, Image, Video, and Decision). Each slot SHALL support an ordered list of provider-model candidates instead of a single binding, with user-controllable priority ordering.

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

#### Scenario: Binding candidates to Decision capability slot
- **WHEN** user configures candidates for the `decision` capability slot
- **THEN** the system persists the decision model candidates to `ai_config.json`
- **AND** the AI configuration UI renders a dedicated slot card for Decision/Reasoning with candidate ordering and health indicators

#### Scenario: Routing requests through capability slot
- **WHEN** a business tool requests completion through a capability slot (e.g., `text` or `decision`) without specifying an explicit provider
- **THEN** the system resolves the provider and model via the slot's ordered candidate list and the auto-healing routing engine

#### Scenario: Backward-compatible loading of legacy single-binding format
- **WHEN** the application loads an `ai_config.json` containing the legacy `defaultSlots` format with single `{providerId, model}` entries
- **THEN** each legacy binding is automatically migrated to a single-element candidate list, and the config is re-saved in the new format without data loss

#### Scenario: Graceful migration when Decision slot is missing from config
- **WHEN** the application loads an `ai_config.json` that lacks the `decision` slot key
- **THEN** the system automatically initializes `decision` with an empty candidate list without failing or corrupting existing slot bindings
