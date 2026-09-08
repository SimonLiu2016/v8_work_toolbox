# Proposal: AI Chat Extended Timeout and Reasoning Model Resilience

## Why
Users interacting with the AI Assistant or executing complex text operations frequently encounter:
```
抱歉，执行过程中出现错误: 槽位 "text" 的全部 1 个候选供应商均不可用：
  候选 1: TimeoutException after 0:00:30.000000: Future not completed
请检查供应商配置或网络连接。
```
Through direct real-world benchmarking on models such as Xiaomi `mimo-v2.5-pro`, deep reasoning and thinking models require 35 to 50 seconds to complete internal thinking tokens generation and synthesize long-form responses. The current codebase enforces a hardcoded 30-second client timeout (`const Duration(seconds: 30)`) across OpenAI, Anthropic, and Gemini protocols in `ai_service.dart`. This prematurely severs valid connections right before the model finishes generating its output.

Furthermore, when models return HTTP 429 (Rate Limit), the current 2000ms delay combined with the 30s timeout often pushes the connection over the edge.

## What Changes
1. **Extended Default Chat Timeout**:
   - Upgrade the default HTTP chat completion timeout in `ai_service.dart` from 30 seconds to 90 seconds across all supported protocols (OpenAI, Anthropic, Gemini).
   - Ensure the timeout covers deep-thinking and reasoning models (`mimo-v2.5-pro`, `o1`, `deepseek-r1`, Claude with extended thinking) without artificial cutoffs.
2. **Dynamic / Adaptive Timeout Parameterization**:
   - Introduce an optional `timeout` override in `AiService.chat()` and `AiRoutingService.chat()` so caller services (e.g. AI Assistant dialog, scheduled batch processing, document summarization) can request up to 120 seconds for deep multi-step agent loops.
3. **Resilient 429 Backoff & Error Details**:
   - Enhance the 429 backoff handling to log detailed wait times and preserve clean error messages when retries are exhausted.
   - Ensure `SlotUnavailableException` captures whether failures were caused by server rate limiting (429) or upstream latency (TimeoutException), providing clearer user-facing recommendations.
