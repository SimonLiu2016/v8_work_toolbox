# Tasks: AI Chat Extended Timeout and Reasoning Model Resilience

## Implementation Tasks

- [x] 1. Update `AiService` and `AiRoutingService` with extended timeout support
  - [x] 1.1 Update default chat timeout from 30s to 90s in `AiService` across OpenAI, Anthropic, and Gemini protocols
  - [x] 1.2 Add optional `Duration? timeout` parameter to `AiService.chat` and `AiRoutingService.chat`
  - [x] 1.3 Update `AiAssistantService._runAgentLoop` to utilize the extended timeout
- [x] 2. Update and run test suites
  - [x] 2.1 Update `ai_routing_test.dart` and `ai_service_protocols_test.dart` to verify custom timeout propagation
  - [x] 2.2 Run full test suite to ensure zero regressions
- [x] 3. Build, deploy, and verify
  - [x] 3.1 Build macOS release binary and redeploy to `/Applications/V8WorkToolbox.app`
  - [x] 3.2 Verify AI Assistant dialogue with reasoning models
