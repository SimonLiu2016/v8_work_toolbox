## MODIFIED Requirements

### Requirement: Model discovery and capability slots
The application SHALL allow discovering available models via authentic provider API requests or manual entry, and assigning models to global capability slots (Text, Multimodal, TTS, STT, Video, Image). Each slot SHALL support an ordered list of provider-model candidates instead of a single binding, with user-controllable priority ordering.

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
- **WHEN** a business tool requests text completion or image generation without specifying an explicit provider
- **THEN** the system resolves the provider and model via the slot's ordered candidate list and the auto-healing routing engine

#### Scenario: Backward-compatible loading of legacy single-binding format
- **WHEN** the application loads an `ai_config.json` containing the legacy `defaultSlots` format with single `{providerId, model}` entries
- **THEN** each legacy binding is automatically migrated to a single-element candidate list, and the config is re-saved in the new format without data loss

## ADDED Requirements

### Requirement: Global Image Generation Capability Slot and Studio Integration
The AI configuration infrastructure SHALL support a dedicated `image` capability slot for text-to-image generation. The AI Video Studio settings SHALL support selecting `system-image` to dynamically use the active provider and model configured in the global `image` slot, providing live status visibility, connectivity testing, and a navigation shortcut to the AI capability configuration tab.

#### Scenario: Configuring global image generation slot
- **WHEN** user navigates to the AI Configuration page and configures a provider (e.g. SiliconFlow, OpenAI) and model in the `image` capability slot
- **THEN** the configuration is saved to `ai_config.json` under `candidateSlots.image` and activated as the primary image generator.

#### Scenario: Video studio uses system-image engine
- **WHEN** user selects "跟随系统全局配置 (system-image)" in AI Video Studio settings
- **THEN** storyboard keyframe generation uses the active provider and model from the global `image` slot, automatically transmitting requests via the standard OpenAI-compatible image generations protocol.

#### Scenario: Studio settings displays dynamic image model status
- **WHEN** user opens the AI Video Studio settings dialog
- **THEN** the dialog displays the currently configured system image provider and model name, or informs the user that the global image slot is not yet configured.

#### Scenario: Testing image generation connectivity in studio settings
- **WHEN** user clicks "测试连通性" for image generation in the studio settings dialog
- **THEN** the system executes a real image generation or connectivity verification against the resolved provider and displays whether the test succeeded or failed with diagnostic details.
