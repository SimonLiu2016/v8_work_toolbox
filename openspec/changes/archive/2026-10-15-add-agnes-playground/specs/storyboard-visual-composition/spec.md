## ADDED Requirements

### Requirement: 首尾帧参考图尺寸守卫

系统 SHALL 对提交给 Agnes 视频模型的首帧与尾帧执行相同的尺寸校验：单边小于 256 像素或大于 5760 像素的图片 SHALL 被拒绝并说明原因；超过传输上限的图片 SHALL 在提交前被等比缩放并重新编码。首帧与尾帧 SHALL 使用同一套守卫逻辑，而不是尾帧跳过校验。

#### Scenario: 尾帧尺寸过小

- **WHEN** 用户提交一张边长为 200 像素的尾帧
- **THEN** 系统 SHALL 拒绝该请求并提示图片尺寸不满足模型要求，SHALL NOT 提交请求

#### Scenario: 超大首帧与尾帧

- **WHEN** 用户提交两张 4000×6000 像素的首帧与尾帧
- **THEN** 两张图 SHALL 都被等比缩放至传输上限内并重新编码后才提交

## MODIFIED Requirements

### Requirement: Agnes video generation payload contract
The video generation adapter for Agnes AI SHALL compose video generation requests with valid payload fields (`model`, `prompt`, `mode`, `seconds`, `size`, `aspect_ratio`), and SHALL strictly conform to Agnes official mode mutual-exclusion rules: in keyframe mode, reference media fields (`images`, `audios`, `videos`) SHALL NOT be included; in reference mode, `first_frame` and `last_frame` SHALL NOT be included; in text mode, no media field SHALL be included. The adapter SHALL support `last_frame` alongside `first_frame`, and SHALL accept either one alone or both together in keyframe mode. The `size` value SHALL come from the model's supported resolution tiers and the `aspect_ratio` value SHALL come from the supported ratio whitelist; values outside either set SHALL NOT be submitted.

#### Scenario: Submitting video generation task for Agnes model
- **WHEN** user clicks generate video clip for a shot with keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing valid `model`, `prompt`, `mode`, `seconds`, `size`, `aspect_ratio`, `first_frame`, `image`, and `image_url`, and receives successful task dispatch

#### Scenario: Submitting video generation task without keyframe
- **WHEN** user triggers video generation for a shot that has no keyframe image
- **THEN** adapter automatically selects text mode, omits `first_frame`, and submits the prompt to Agnes video model

#### Scenario: Submitting video generation task for Agnes model in keyframe mode
- **WHEN** user triggers video generation with a keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing `model`, `prompt`, `mode: "keyframe"`, `seconds`, `size`, `aspect_ratio`, and `first_frame`, strictly excluding `images`, `audios`, or `videos`, and receives successful task dispatch

#### Scenario: Submitting video generation task for Agnes model with redundant frame bindings
- **WHEN** user triggers video generation with a keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing valid `model`, `prompt`, `mode`, `seconds`, `size`, `aspect_ratio`, and `first_frame`, and receives successful task dispatch

#### Scenario: Submitting with both first and last frames
- **WHEN** user triggers video generation with both a first-frame and a last-frame image
- **THEN** adapter submits payload containing both `first_frame` and `last_frame` in keyframe mode, and does not require the first frame to be present when only a last frame is supplied

#### Scenario: Submitting with reference images only
- **WHEN** user triggers video generation with reference images but no first or last frame
- **THEN** adapter selects reference mode, submits the images in the reference media array, and omits `first_frame` and `last_frame`

#### Scenario: Submitting without any media
- **WHEN** user triggers video generation with only a prompt and no media input
- **THEN** adapter automatically selects text mode, omits all media fields, and submits the prompt to Agnes video model

#### Scenario: Requested resolution tier outside model support
- **WHEN** user requests a resolution tier that the selected model does not support (for example `1080P` on the Flash variant)
- **THEN** the adapter submits a tier the model supports, records the snap in the AI log, and does not submit a value outside the model's declared set

#### Scenario: Requested duration exceeds declared maximum
- **WHEN** user requests a 15-second Agnes clip and the declared model supports at most 12 seconds
- **THEN** the adapter submits `seconds` of 12, records the snap in the AI log, and does not submit a value outside the declared set

#### Scenario: Handling transient upstream rate limits (HTTP 429)
- **WHEN** Agnes video gateway returns HTTP 429 indicating upstream overload
- **THEN** adapter automatically retries up to 4 times with exponential backoff delay, reporting retry progress, before failing the task

### Requirement: 中转站 Agnes Video 2.5 Flash 视频生成适配
系统 SHALL 在视频生成适配层提供对 `agnes-video-2.5-flash` 的完整集成。系统 SHALL 向 `POST /v1/videos` 发起任务创建请求（参数包括 `model: "agnes-video-2.5-flash"`, `mode`, `size: "720P"`, `aspect_ratio`, `seconds`, 以及按模式所需的 `first_frame` / `last_frame` / 参考媒体数组，图片接受 Data URI），并异步轮询 `/agnesapi?video_id=...&model_name=agnes-video-2.5-flash` 或 `/v1/videos/{id}`，直到状态为 `completed` 后自动下载成片 MP4 到本地。

#### Scenario: 成功调用 Agnes Video 生成 5 秒视频片段
- **WHEN** 用户或队列针对已有关键帧的分镜触发视频生成
- **THEN** 系统创建视频生成任务并轮询进度，任务完成后将成片 MP4 保存至分镜对应目录并将分镜状态标记为已完成

#### Scenario: Flash 型号提交非 720P 档位
- **WHEN** 用户为 `agnes-video-2.5-flash` 请求 `1080P` 或 `2K` 档位
- **THEN** 系统 SHALL 提交 `720P` 并在日志中记录该吸附，SHALL NOT 提交会导致上游 HTTP 400 的档位值
