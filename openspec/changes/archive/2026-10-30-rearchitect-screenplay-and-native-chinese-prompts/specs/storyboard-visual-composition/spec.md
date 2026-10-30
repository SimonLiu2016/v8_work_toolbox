## MODIFIED Requirements

### Requirement: Action and environment prompt assembly

The system SHALL combine storyboard shot visual action descriptions (`action_zh`), active scene configurations (`description_zh`), and stylistic tokens using native Chinese cinematic director syntax into the positive generation prompt, ensuring accurate visual correspondence with scripted actions and native semantic understanding.

The assembled prompt MUST NOT inject redundant or conflicting legacy English rendering tags (such as `Unreal Engine 5 render`, `Octane render`, `3D CGI animation`, `masterpiece, 8k`), and MUST NOT concatenate disjointed English prompt fragments with Chinese prose when dispatching requests to vision and video generative models.

#### Scenario: Generate frame with scripted action and scene
- **WHEN** user triggers keyframe or video generation for a shot containing action descriptions (e.g. 雨夜长街青石板路上的疾跑踩水) and an assigned scene
- **THEN** system compiles a pure, coherent native Chinese director prompt combining scene environment, dynamic lighting, and action semantics without English token noise
- **AND** the assembled prompt is sent to the vision model preserving cultural nuances and cinematic framing

### Requirement: Character visual anchoring

The system SHALL pass active character descriptions—including Chinese facial characteristics (`facial_features_zh`), body morphology, and attire design (`default_attire_zh`), alongside visual reference images—directly to the generative adapter in native Chinese. The system MUST NOT force translation into fragmented English tags (`facial_prompt`, `attire_prompt`) when submitting to Chinese multimodal foundation models.

#### Scenario: Keyframe generation for character shot
- **WHEN** keyframe generation is triggered for a shot featuring a specific character
- **THEN** system binds the character's native Chinese appearance and attire descriptors together with anchor reference images
- **AND** maintains cross-shot character identity consistency without English prompt contamination
