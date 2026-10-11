## ADDED Requirements

### Requirement: Agnes video generation payload contract
The video generation adapter for Agnes AI SHALL compose video generation requests with valid payload fields (`model`, `prompt`, `mode: keyframe`, `seconds`, `aspect_ratio`, `first_frame`), and SHALL NOT include invalid parameter enums such as `'size': '720P'` that cause upstream gateway 400 rejection (`plugin usage enum is not an allowed value`).

#### Scenario: Submitting video generation task for Agnes model
- **WHEN** user clicks generate video clip for a shot with keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing valid `model`, `prompt`, `mode`, `seconds`, `aspect_ratio`, and `first_frame`, without any invalid `size` enum parameter, and receives successful task dispatch

### Requirement: Storyboard card and thumbnail null-safe rendering
The storyboard board and thumbnail widgets SHALL cache media file references in local immutable variables during render passes, and SHALL NOT execute unchecked null assertion operator (`!`) on dynamically evaluated file getters.

#### Scenario: Keyframe generation completion and thumbnail update
- **WHEN** keyframe generation completes and triggers state reload on the storyboard board
- **THEN** thumbnail and card widgets render the newly saved frame image without throwing `Null check operator used on a null value`
