## MODIFIED Requirements

### Requirement: Agnes video generation payload contract
The video generation adapter for Agnes AI SHALL compose video generation requests with valid payload fields (`model`, `prompt`, `mode: keyframe`, `seconds`, `aspect_ratio`, `first_frame`), and SHALL strictly conform to Agnes official mode mutual-exclusion rules: in `mode: keyframe`, reference media fields (`image`, `images`, `audios`, `videos`) SHALL NOT be included, preventing upstream HTTP 400 rejection (`首尾帧素材与参考素材不能同时使用`). It SHALL NOT include invalid parameter enums such as `'size': '720P'` that cause upstream gateway 400 rejection (`plugin usage enum is not an allowed value`).

#### Scenario: Submitting video generation task for Agnes model in keyframe mode
- **WHEN** user clicks generate video clip for a shot with keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing `model`, `prompt`, `mode: keyframe`, `seconds`, `aspect_ratio`, and `first_frame`, strictly excluding `image`, `images`, `audios`, or `videos`, and receives successful task dispatch

#### Scenario: Submitting video generation task for Agnes model
- **WHEN** user clicks generate video clip for a shot with keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing valid `model`, `prompt`, `mode`, `seconds`, `aspect_ratio`, and `first_frame`, without any invalid `size` enum parameter, and receives successful task dispatch

#### Scenario: Requested duration exceeds declared maximum
- **WHEN** user requests a 15-second Agnes clip and the declared model supports at most 12 seconds
- **THEN** the adapter submits `seconds` of 12, records the snap in the AI log, and does not submit a value outside the declared set
