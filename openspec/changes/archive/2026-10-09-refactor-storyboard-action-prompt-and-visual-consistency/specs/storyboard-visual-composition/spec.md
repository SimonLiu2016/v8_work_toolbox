## Purpose

Defines the visual prompt assembly and composition rules for storyboard keyframe image generation, ensuring cinematic actions, scene context, and character consistency are reflected in generated frames.

## ADDED Requirements

### Requirement: Action and environment prompt assembly
The system SHALL combine storyboard shot visual action descriptions (`action_zh`), active scene configurations, and stylistic tokens into the positive image generation prompt, ensuring visual correspondence with scripted actions.

#### Scenario: Generate frame with scripted action and scene
- **WHEN** user triggers keyframe generation for a shot containing action descriptions (e.g. footsteps splashing in puddles on a rainy street) and an assigned scene
- **THEN** system includes the visual action semantics and the scene environment into the assembled image prompt sent to the vision model

### Requirement: Human suppression for establishing and empty shots
The system SHALL inject negative human prompts when a shot does not specify any character IDs, preventing unsolicited human faces from polluting establishing or environmental shots.

#### Scenario: Keyframe generation for empty establishing shot
- **WHEN** keyframe generation is triggered for an establishing shot without any character assigned
- **THEN** system injects human negative constraints (e.g. `person, human, face, character, portrait`) into the negative prompt to guarantee a clean landscape or scene shot

### Requirement: Character visual anchoring
The system SHALL pass the active character configuration (including reference anchor images when available) to the generation adapter, anchoring facial features and clothing across shots featuring the character.

#### Scenario: Keyframe generation for character shot
- **WHEN** keyframe generation is triggered for a shot featuring a specific character
- **THEN** system binds the character's base positive prompt and reference image to maintain cross-shot character consistency
