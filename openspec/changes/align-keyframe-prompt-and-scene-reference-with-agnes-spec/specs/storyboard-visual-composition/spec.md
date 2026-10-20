## MODIFIED Requirements

### Requirement: Action and environment prompt assembly
The system SHALL assemble storyboard shot keyframe generation prompts conforming to the Agnes Image multimodal specification. When multiple reference images (characters and scenes) are supplied, the prompt SHALL explicitly declare each reference image's role (`[参考图角色]`, e.g. "将第一张图作为主要角色，第二张图作为背景场景参考") and specify the preservation constraints (`[需要保留的元素]`, e.g. 保留第一张图的角色身份与第二张图的场景空间布局). The prompt structure SHALL prioritize the shot's core visual action and dramatic focus (`[主体核心动作与视觉焦点]`) in the high-attention front section before static secondary attributes. Environmental details SHALL be extracted from the active `SceneCard` and matched spatial view's detailed Chinese description (`description_zh`) instead of relying on `prompt_en` or falling back to five-character names.

#### Scenario: Generate frame with scripted action and scene
- **WHEN** user triggers keyframe generation for a shot containing action descriptions (e.g. 姜七夜单手按刀，指尖轻敲刀鞘) and an assigned scene with rich Chinese spatial descriptions
- **THEN** system places the action description and camera focal point at the forefront of the prompt and incorporates the scene's detailed Chinese physical atmosphere (e.g. 粗木铁栏水牢、旧案刑架与昏黄油灯) into the environment section

#### Scenario: Multi-image reference role declaration
- **WHEN** keyframe generation is executed with multiple reference images comprising character turnarounds and scene spatial views
- **THEN** system prefixes the prompt with explicit multi-image role directives specifying each image's character or scene role and which identity or architectural layout features must be preserved

### Requirement: Character visual anchoring
The system SHALL pass active character reference images (three-view turnaround sheets or face anchors) to the generation adapter, anchoring facial features, hairstyle, and costume. In the text prompt, character descriptions SHALL be formatted as concise identity anchors rather than redundant full-body multi-hundred-word text descriptions that overwhelm visual action weights.

#### Scenario: Keyframe generation for character shot
- **WHEN** keyframe generation is triggered for a shot featuring one or more characters with existing turnaround assets
- **THEN** system binds character turnaround images into the multi-image payload and includes concise character identity anchors in the prompt, preserving high attention weight for the shot's active dramatic action

## ADDED Requirements

### Requirement: Scene and spatial reference injection for keyframes
The system SHALL resolve the active `SceneCard` matching the shot's `sceneId` and pass it to the keyframe generation task runner (`ImageGenTask`). The task runner SHALL automatically resolve the corresponding spatial view reference image (e.g. `spatial_front`, `spatial_back`) and inject it into the image generation adapter's reference images list alongside character turnaround images.

#### Scenario: Trigger keyframe generation from storyboard board
- **WHEN** user triggers keyframe generation for a shot bound to a scene card with spatial profile images
- **THEN** system resolves the scene card, extracts the matching spatial profile image path, and includes it in `ImageGenRequest.referenceImages` so the image model receives both character and scene references

### Requirement: Environment-aware style token filtering
The system SHALL inspect the shot's scene setting (e.g. indoor, underground jail, secret chamber vs. open mountain/outdoor) and filter out contradictory landscape tokens (such as `云海雾气`, `广阔天地`, `日落霞光`) from the positive style baseline when generating indoor or subterranean keyframes, replacing them with appropriate interior lighting and enclosed atmosphere descriptors.

#### Scenario: Generating indoor jail keyframe with generic donghua style
- **WHEN** keyframe generation is triggered for a subterranean jail scene under a Chinese fantasy style preset that includes `云海雾气`
- **THEN** system automatically suppresses outdoor cloud and mountain tokens from the prompt and injects indoor ambient lighting tokens (e.g. `昏暗油灯微光`, `阴冷潮湿质感`)
