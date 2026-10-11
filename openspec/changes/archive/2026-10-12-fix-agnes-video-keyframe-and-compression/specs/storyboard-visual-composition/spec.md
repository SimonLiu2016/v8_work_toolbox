## MODIFIED Requirements

### Requirement: Agnes video generation payload contract
The video generation adapter for Agnes AI SHALL compose video generation requests with valid payload fields (`model`, `prompt`, `mode`, `seconds`, `aspect_ratio`), pre-compress keyframe images before Base64 encoding to prevent proxy truncation, support dynamic mode selection (`keyframe` vs `text`), and implement exponential backoff retry for transient upstream rate limit responses (`HTTP 429`). The adapter SHALL NOT include invalid parameter enums such as `'size': '720P'`.

#### Scenario: Submitting video generation task for Agnes model in keyframe mode
- **WHEN** user clicks generate video clip for a shot with keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing `model`, `prompt`, `mode: keyframe`, `seconds`, `aspect_ratio`, and `first_frame`, strictly excluding `image`, `images`, `audios`, or `videos`, and receives successful task dispatch

#### Scenario: Submitting video generation task for Agnes model
- **WHEN** user clicks generate video clip for a shot with keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing valid `model`, `prompt`, `mode`, `seconds`, `aspect_ratio`, and compressed `first_frame`, without any invalid `size` enum parameter, and receives successful task dispatch

#### Scenario: Submitting video generation task without keyframe
- **WHEN** user triggers video generation for a shot that has no keyframe image
- **THEN** adapter automatically selects `mode: "text"`, omits `first_frame`, and submits the prompt to Agnes video model

#### Scenario: Handling transient upstream rate limits (HTTP 429)
- **WHEN** Agnes video gateway returns HTTP 429 indicating upstream overload
- **THEN** adapter automatically retries up to 4 times with exponential backoff delay, reporting retry progress, before failing the task

#### Scenario: Requested duration exceeds declared maximum
- **WHEN** user requests a 15-second Agnes clip and the declared model supports at most 12 seconds
- **THEN** the adapter submits `seconds` of 12, records the snap in the AI log, and does not submit a value outside the declared set
