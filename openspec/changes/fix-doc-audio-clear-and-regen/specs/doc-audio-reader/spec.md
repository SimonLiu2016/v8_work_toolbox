## ADDED Requirements

### Requirement: Clear current document

The system SHALL provide a "关闭文档" action in the reader AppBar (available only when a document is loaded) that stops playback, clears the current document from the controller state, and returns the UI to the empty-state guidance card. The action MUST NOT affect other documents' cached audio. Optionally, the clear operation MAY also clear the current document's audio cache when the user explicitly chooses to free disk space.

#### Scenario: Close loaded document returns to empty state

- **WHEN** user clicks "关闭文档" while a document is loaded
- **THEN** playback stops, the controller's document reference is cleared, and the reader body returns to the empty-state guidance card showing import options

#### Scenario: Close document does not affect other documents

- **WHEN** user closes document A after previously having cached audio for document B
- **THEN** document B's audio cache remains intact and available when document B is reopened later

#### Scenario: Close button disabled when no document loaded

- **WHEN** no document is currently loaded
- **THEN** the "关闭文档" button is disabled or hidden

### Requirement: TTS config change triggers explicit cache invalidation and re-synthesis

When the user changes TTS configuration fields that affect synthesis output (mode, voice ID, provider, model) and a document is currently loaded, the system SHALL present an explicit confirmation dialog warning that the change will clear the current document's audio cache and trigger re-synthesis (which may incur paid AI API costs for custom AI mode). Only after user confirmation SHALL the system clear the current document's cache and re-synthesize using the new configuration. Changes to playback-only fields (speech rate, volume) MUST NOT trigger cache clearing or re-synthesis, as these are applied in real-time by the audio player without re-synthesis.

#### Scenario: Synthesis-affecting config change with document loaded

- **WHEN** user changes voice ID or synthesis mode while a document is loaded
- **THEN** system presents a confirmation dialog: "音色变更将清空当前文档缓存并重新合成（customAi 模式为付费调用），是否继续？"
- **AND** upon confirmation, system clears the current document's audio cache, applies the new config, and re-synthesizes the first chunk for immediate playback

#### Scenario: Playback-only config change does not clear cache

- **WHEN** user changes only speech rate or volume
- **THEN** the new setting is applied in real-time by the audio player without clearing any cached audio or triggering re-synthesis

#### Scenario: Config change with no document loaded

- **WHEN** user changes TTS config while no document is loaded
- **THEN** the config is persisted and no confirmation dialog or cache clearing is needed

#### Scenario: User declines re-synthesis

- **WHEN** user dismisses the confirmation dialog without confirming
- **THEN** the config change is not applied, the current document's cache remains intact, and playback continues with the previous configuration

## MODIFIED Requirements

### Requirement: TTS configuration persistence and smart mode defaulting
The system SHALL persist the user's TTS configuration (synthesis mode, selected provider, model, voice ID, and speech rate) to local application storage, and automatically resolve a functional default mode on startup. When a config change affecting synthesis output (mode, voice, provider, model) is applied while a document is loaded, the system SHALL invalidate the current document's audio cache and re-synthesize chunks on demand with the new configuration. Playback-only parameters (speech rate, volume) SHALL be applied by the audio player in real-time without triggering cache invalidation or re-synthesis.

#### Scenario: Persisting user TTS configuration changes

- **WHEN** user changes the TTS synthesis mode, voice, speed, or provider settings
- **THEN** system immediately saves the configuration to local application storage

#### Scenario: Restoring configuration across application restarts

- **WHEN** user opens the audio reader after an application restart
- **THEN** system loads and applies the previously saved TTS configuration instead of reverting to default Edge-TTS

#### Scenario: Smart initial default when AI provider configured

- **WHEN** the audio reader opens without prior saved configuration and the system AI configuration contains an active TTS model provider
- **THEN** system automatically defaults the synthesis mode to Custom AI TTS using the configured provider and model rather than defaulting to Edge-TTS

#### Scenario: Synthesis-affecting change invalidates current document cache

- **WHEN** user applies a new voice or mode while a document is loaded and confirms the re-synthesis prompt
- **THEN** system clears the current document's chunk audio cache so subsequent playback re-synthesizes with the new voice or mode, rather than replaying stale audio from the old configuration

#### Scenario: Playback parameter change does not invalidate cache

- **WHEN** user adjusts speech rate or volume
- **THEN** the audio player applies the change in real-time and no cached audio is cleared or re-synthesized
