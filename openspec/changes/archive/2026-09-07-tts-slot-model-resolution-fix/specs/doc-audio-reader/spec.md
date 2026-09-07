## ADDED Requirements

### Requirement: System TTS slot model priority resolution
The system SHALL resolve the synthesis model name from the active TTS slot bindings for the matched provider with highest priority when system AI configuration is selected, falling back to provider model inspection and provider-specific model defaults.

#### Scenario: Slot candidate model extraction with explicit systemProviderId
- **WHEN** user selects a specific systemProviderId and useSystemAiConfig is true
- **THEN** system queries the TTS slot bindings for that provider and resolves its configured model (e.g., mimo-v2.5-tts) instead of falling back to default tts-1

#### Scenario: MiMo model fallback protection
- **WHEN** the resolved provider is Xiaomi MiMo and the resolved model is empty or default tts-1
- **THEN** system automatically substitutes mimo-v2.5-tts as the model name
