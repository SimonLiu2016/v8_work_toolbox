## MODIFIED Requirements

### Requirement: Storyboard card and thumbnail null-safe rendering
The storyboard board and thumbnail widgets SHALL cache media file references in local immutable variables during render passes, and SHALL NOT execute unchecked null assertion operator (`!`) on dynamically evaluated file getters.

#### Scenario: Keyframe generation completion and thumbnail update
- **WHEN** keyframe generation completes and triggers state reload on the storyboard board
- **THEN** thumbnail and card widgets render the newly saved frame image without throwing `Null check operator used on a null value`

## ADDED Requirements

### Requirement: Long-form novel deconstruction timeout resilience
The system SHALL allocate extended timeout thresholds (at least 240 seconds) for deep novel deconstruction tasks (`novelMasterExtraction` and `novelEpisodeSegmentation`), preventing premature client-side `TimeoutException` aborts when using reasoning and long-context LLMs.

#### Scenario: Importing long novel text with reasoning model
- **WHEN** user imports novel text into Idea Incubator and the underlying model takes more than 120 seconds to produce structured JSON assets
- **THEN** system maintains the connection up to the extended timeout threshold without throwing `TimeoutException after 0:02:00.000000`, successfully parsing and saving characters, scenes, and episodes

### Requirement: Live elapsed time display during novel import
The system SHALL provide a live updating ticker showing elapsed seconds during the novel deconstruction phases, giving visual confirmation of ongoing background processing.

#### Scenario: User imports novel file
- **WHEN** novel import starts
- **THEN** the UI displays the current phase along with an increasing elapsed seconds counter (e.g. `已耗时 12s`)
