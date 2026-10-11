# storyboard-visual-composition Specification

## Purpose
Defines the visual prompt assembly and composition rules for storyboard keyframe image generation, ensuring cinematic actions, scene context, and character consistency are reflected in generated frames.
## Requirements
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

### Requirement: Storyboard card and thumbnail null-safe rendering
The storyboard board and thumbnail widgets SHALL cache media file references in local immutable variables during render passes, and SHALL NOT execute unchecked null assertion operator (`!`) on dynamically evaluated file getters.

#### Scenario: Keyframe generation completion and thumbnail update
- **WHEN** keyframe generation completes and triggers state reload on the storyboard board
- **THEN** thumbnail and card widgets render the newly saved frame image without throwing `Null check operator used on a null value`

<!-- 归并自 ai-video-studio 顶层 spec（2026-10-12）。与上方
     "Agnes video generation payload contract" 的分工：那条管请求体字段与
     互斥规则，这条管完整任务生命周期（创建→轮询→下载）。 -->

### Requirement: 中转站 Agnes Video 2.5 Flash 视频生成适配
系统 SHALL 在视频生成适配层提供对 `agnes-video-2.5-flash` 的完整集成。系统 SHALL 向中转站 `POST /v1/videos` 发起任务创建请求（参数包括 `model: "agnes-video-2.5-flash"`, `mode: "keyframe"`, `size: "720P"`, `aspect_ratio: "9:16"`, `seconds: "5"`, `first_frame: "<图片URL/DataURI>"`），并异步轮询 `/agnesapi?video_id=...` 或 `/v1/videos/{id}`，直到状态为 `completed` 后自动下载成片 MP4 到本地。

#### Scenario: 成功调用 Agnes Video 生成 5 秒视频片段
- **WHEN** 用户或队列针对已有关键帧的分镜触发视频生成
- **THEN** 系统向中转站创建视频生成任务并轮询进度，任务完成后将成片 MP4 保存至分镜对应目录并将分镜状态标记为已完成

### Requirement: Agnes gateway resilience and transient error retry
The video generation adapter for Agnes AI SHALL automatically retry task dispatch upon receiving transient upstream gateway errors, including HTTP 429 (rate limiting / saturation), HTTP 502/503/504 (bad gateway / queue full), and HTTP 400 with message indicating missing first_frame/last_frame caused by gateway parameter drop, applying exponential backoff with jitter to rotate to a healthy upstream node.

#### Scenario: Gateway routing to node with dropped parameters
- **WHEN** video dispatch request hits an upstream gateway node that drops `first_frame` and returns HTTP 400 with `keyframe 模式需要 first_frame 或 last_frame`
- **THEN** adapter catches the transient gateway failure, waits with backoff, and retries the dispatch, successfully rotating to a healthy upstream node without crashing or immediately aborting the user task

#### Scenario: Upstream video queue saturated
- **WHEN** upstream video queue returns HTTP 429 or HTTP 503 indicating queue saturation
- **THEN** adapter logs the queue status, informs the user via progress updates, and retries up to the configured retry threshold before declaring failure

