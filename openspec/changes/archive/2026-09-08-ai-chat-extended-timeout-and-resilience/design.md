# Design: AI Chat Extended Timeout and Reasoning Model Resilience

## Architecture & Implementation Strategy

### 1. Default Timeout Constants in `AiService`
Currently, `_chatOpenAi`, `_chatAnthropic`, and `_chatGemini` all use `const Duration(seconds: 30)`.
- Introduce `static const Duration defaultChatTimeout = Duration(seconds: 90);`
- Introduce `static const Duration defaultProbeTimeout = Duration(seconds: 15);` (for ping/model discovery)
- Add an optional `Duration? timeout` parameter to:
  - `AiService.chat({..., Duration? timeout})`
  - `AiRoutingService.chat({..., Duration? timeout})`
  - Protocol dispatchers `_chatOpenAi`, `_chatAnthropic`, `_chatGemini`

### 2. Adaptive Timeouts for AI Assistant Agent Loop
In `lib/tools/ai_assistant/services/ai_assistant_service.dart`:
- When calling `AiService.instance.chat()`, pass `timeout: const Duration(seconds: 90)` (or 120s if multiple tools were invoked).
- This ensures that thinking models like `mimo-v2.5-pro` (which benchmarked at 36.4s) have ample runway to return responses without timing out.

### 3. Enhanced 429 Retry Strategy
In protocol handlers:
- When a 429 is encountered, wait 2500ms and execute the retry with the remaining duration of the requested timeout, or a full 60s timeout for the retry attempt, rather than a truncated deadline.

## Trade-offs and Considerations
- **UI Responsiveness**: A 90s timeout means that if an endpoint completely hangs with no response, the user waits longer before seeing a failure. However, during normal streaming/generation of reasoning models, 30s was actively producing false-positive failures for successful completions. 90s is the sweet spot aligned with OpenAI, Anthropic, and Google official client SDK defaults (which range between 60s and 600s).
