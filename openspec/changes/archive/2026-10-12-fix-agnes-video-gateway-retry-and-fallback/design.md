## Context

See `proposal.md` for background and probe analysis. The gateway (`http://119.29.249.154:3356`) balances requests across an upstream channel pool for `agnes-video-2.5-flash`. A subset of upstream channels suffers from parameter forwarding loss (`first_frame` dropped, returning HTTP 400), while healthy channels enter video generation or return rate limit (429) / queue full (503).

## Goals / Non-Goals

**Goals:**
- Make `AgnesVideoAdapter._post` resilient to multi-channel gateway routing fluctuations.
- Add multi-key parameter redundancy (`first_frame`, `image`, `image_url`) in the dispatch payload.
- Treat upstream proxy errors (HTTP 400 with `first_frame`, 502, 503, 504, and 429) as retriable with exponential backoff and jitter.
- Surface human-friendly progress messages during retries.

**Non-Goals:**
- Modifying New API backend server configuration or server reverse proxy code (we do not control the remote server infrastructure).
- Changing keyframe image compression or scaling logic (already stabilized in previous change).

## Decisions

### Decision 1: Expand retriable status codes and messages in `_post`
- **Choice**: In `AgnesVideoAdapter._post`, inspect both HTTP status code and response body.
  - Retriable conditions:
    1. HTTP 429: Upstream concurrency / rate limit saturated.
    2. HTTP 502 / 503 / 504: Upstream gateway or video processing queue saturated.
    3. HTTP 400 with body containing `"keyframe 模式需要 first_frame"` or `"first_frame 或 last_frame"`: Upstream node dropped image parameter; rotating channel via retry can hit a healthy node.
- **Alternatives considered**: Only retry on 5xx and 429. Rejected because HTTP 400 from bad channels immediately causes generation failure when users click "视频".

### Decision 2: Redundant payload fields for keyframe mode
- **Choice**: When `mode == 'keyframe'`, inject `first_frame: dataUri`, `image: dataUri`, and `image_url: dataUri`.
- **Alternatives considered**: Only send `first_frame`. Rejected because upstream reverse proxies using different SDK conventions (e.g. standard OpenAI vision / Midjourney adapter / Luma adapter) may expect `image` or `image_url`.

### Decision 3: Jittered backoff and retry count
- **Choice**: Set `maxRetries = 4` (total 5 attempts). Backoff base `2000ms`, multiplied by attempt index with 500-1000ms random jitter, allowing enough time for queue drainage and channel rotation.
- **Alternatives considered**: Immediate retry without delay. Rejected because it can trigger IP-level rate limiting on the gateway.

## Risks / Trade-offs

- **[Risk] High load delays task response**: If all upstream channels are busy (429/503), retrying 4 times can take ~15-20 seconds before giving up.
  - *Mitigation*: Output progress notifications like `正在排队接入视频生成通道 (第 2/5 次尝试)...` via adapter progress callbacks or log lines so the UI is responsive.
