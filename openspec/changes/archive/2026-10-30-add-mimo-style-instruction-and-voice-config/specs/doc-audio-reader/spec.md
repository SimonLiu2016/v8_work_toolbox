## MODIFIED Requirements

### Requirement: OpenAI Chat Audio Completions and Xiaomi MiMo adaptation
The system SHALL dynamically detect Chat Audio Completions models (such as Xiaomi MiMo `mimo-v2.5-tts` or OpenAI chat audio models), routing synthesis requests to `/v1/chat/completions` with assistant messages and audio configurations, and decoding Base64 audio payloads. When targeting Xiaomi MiMo, the system SHALL support an optional natural-language style instruction conveyed via a user message, and SHALL translate the synthesis speed into an instruction fragment when the provider does not expose a numeric speed parameter.

#### Scenario: Xiaomi MiMo TTS model synthesis
- **WHEN** user selects a Xiaomi MiMo TTS model or provider via system AI config or manual settings
- **THEN** system routes the request to POST /v1/chat/completions with role assistant content and audio format configuration, and decodes the Base64 audio data from the response

#### Scenario: Incompatible voice fallback protection
- **WHEN** a synthesis request targets Xiaomi MiMo but the active voice is not in MiMo's supported voice list
- **THEN** system automatically substitutes `mimo_default` as the synthesis voice to prevent HTTP 400 parameter errors

#### Scenario: Style instruction injected as user message
- **WHEN** a synthesis request targets Xiaomi MiMo and a style instruction is configured (e.g. "自然、清晰、语速适中、略带情感")
- **THEN** the request body SHALL include a `user`-role message carrying the style instruction BEFORE the `assistant`-role message that carries the synthesis text
- **AND** the response audio SHALL be synthesized according to the instructed pacing, tone, and emotion rather than the neutral default

#### Scenario: No user message when instruction absent
- **WHEN** a synthesis request targets Xiaomi MiMo and no style instruction is configured
- **THEN** the request body SHALL contain only the `assistant`-role message (no empty `user` message), preserving existing behavior

#### Scenario: Speed translated to instruction fragment
- **WHEN** a synthesis request targets Xiaomi MiMo with a speed multiplier other than 1.0
- **THEN** the system SHALL append a speed instruction fragment (e.g. "语速加快" for faster, "语速放慢" for slower) to the style instruction rather than sending a numeric `speed` parameter the provider does not support
- **AND** speed 1.0 SHALL NOT add any fragment

#### Scenario: Non-MiMo engines ignore style instruction
- **WHEN** a synthesis request targets a non-MiMo provider (OpenAI speech, Qwen DashScope, Edge, or macOS native)
- **THEN** the style instruction SHALL be ignored and the existing request format preserved

### Requirement: TTS configuration persistence and smart mode defaulting
The system SHALL persist the reader's TTS synthesis configuration (mode, voice, speed, pitch, style instruction, and system-provider binding) to a local config file and SHALL derive a sensible default on first run by inspecting enabled providers and the TTS slot binding.

#### Scenario: Persisting user TTS configuration changes
- **WHEN** user changes the TTS synthesis mode, voice, speed, or provider settings
- **THEN** system immediately saves the configuration to local application storage

#### Scenario: Restoring configuration across application restarts
- **WHEN** user opens the audio reader after an application restart
- **THEN** system loads and applies the previously saved TTS configuration instead of reverting to default Edge-TTS

#### Scenario: Smart initial default when AI provider configured
- **WHEN** the audio reader opens without prior saved configuration and the system AI configuration contains an active TTS model provider
- **THEN** system automatically defaults the synthesis mode to Custom AI TTS using the configured provider and model rather than defaulting to Edge-TTS

#### Scenario: Style instruction persisted with config
- **WHEN** user saves a reader configuration containing a non-empty style instruction
- **THEN** the style instruction is written to the reader config file and restored on the next launch
- **AND** an empty style instruction is also persisted (round-trip preserves emptiness)

#### Scenario: Smart default seeds a MiMo-friendly style instruction
- **WHEN** the reader derives its first-run default and the TTS slot is bound to a MiMo provider
- **THEN** the default style instruction SHALL be a non-empty conservative value (e.g. "自然、清晰、语速适中、略带情感") so out-of-the-box MiMo synthesis is not flat/neutral
- **AND** the default voice SHALL be `mimo_default`
