## MODIFIED Requirements

### Requirement: Agnes video generation payload contract
The video generation adapter for Agnes AI SHALL compose video generation requests with valid payload fields (`model`, `prompt`, `mode: keyframe`, `seconds`, `aspect_ratio`, `first_frame`), and SHALL provide redundant image parameter bindings (`image`, `image_url`) alongside `first_frame` in keyframe mode to ensure maximum gateway and upstream plugin compatibility. It SHALL NOT include invalid parameter enums such as `'size': '720P'` that cause upstream gateway 400 rejection (`plugin usage enum is not an allowed value`).

#### Scenario: Submitting video generation task for Agnes model in keyframe mode
- **WHEN** user clicks generate video clip for a shot with keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing `model`, `prompt`, `mode: keyframe`, `seconds`, `aspect_ratio`, and `first_frame`, strictly excluding `image`, `images`, `audios`, or `videos`, and receives successful task dispatch

#### Scenario: Submitting video generation task for Agnes model
- **WHEN** user clicks generate video clip for a shot with keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing valid `model`, `prompt`, `mode`, `seconds`, `aspect_ratio`, `first_frame`, `image`, and `image_url`, without invalid `size` enum parameter, and receives successful task dispatch

#### Scenario: Submitting video generation task without keyframe
- **WHEN** user triggers video generation for a shot that has no keyframe image
- **THEN** adapter automatically selects `mode: "text"`, omits `first_frame`, and submits the prompt to Agnes video model

#### Scenario: Handling transient upstream rate limits (HTTP 429)
- **WHEN** Agnes video gateway returns HTTP 429 indicating upstream overload
- **THEN** adapter automatically retries up to 4 times with exponential backoff delay, reporting retry progress, before failing the task

#### Scenario: Requested duration exceeds declared maximum
- **WHEN** user requests a 15-second Agnes clip and the declared model supports at most 12 seconds
- **THEN** the adapter submits `seconds` of 12, records the snap in the AI log, and does not submit a value outside the declared set

## ADDED Requirements

### Requirement: Agnes gateway resilience and transient error retry
The video generation adapter for Agnes AI SHALL automatically retry task dispatch upon receiving transient upstream gateway errors, including HTTP 429 (rate limiting / saturation), HTTP 502/503/504 (bad gateway / queue full), and HTTP 400 with message indicating missing first_frame/last_frame caused by gateway parameter drop, applying exponential backoff with jitter to rotate to a healthy upstream node.

#### Scenario: Gateway routing to node with dropped parameters
- **WHEN** video dispatch request hits an upstream gateway node that drops `first_frame` and returns HTTP 400 with `keyframe 模式需要 first_frame 或 last_frame`
- **THEN** adapter catches the transient gateway failure, waits with backoff, and retries the dispatch, successfully rotating to a healthy upstream node without crashing or immediately aborting the user task

#### Scenario: Upstream video queue saturated
- **WHEN** upstream video queue returns HTTP 429 or HTTP 503 indicating queue saturation
- **THEN** adapter logs the queue status, informs the user via progress updates, and retries up to the configured retry threshold before declaring failure
