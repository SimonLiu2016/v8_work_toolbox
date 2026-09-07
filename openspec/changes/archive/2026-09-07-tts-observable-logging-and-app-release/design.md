## Context

See `proposal.md` for motivation.

## Goals / Non-Goals

**Goals:**
- Instrument `OpenAiTtsEngine` and `EdgeTtsEngine` with `AiLogger` so users can inspect real-time TTS events in the in-app AI Log Viewer.
- Rebuild the macOS binary and refresh `/Applications/V8WorkToolbox.app`.

**Non-Goals:**
- Altering the existing TTS synthesis protocols, models, or caching pipelines.

## Decisions

### Decision 1: Structured Telemetry via Existing `AiLogger`
- **Choice**: Call `AiLogger.logRequest`, `AiLogger.logResponse`, and `AiLogger.logError` in `OpenAiTtsEngine` and `EdgeTtsEngine`.
- **Rationale**: Reuses the established AI telemetry buffer displayed in `AiLogDialog`, presenting a unified view across chat, vision, and speech tasks.

### Decision 2: Stopwatch Latency Measurement
- **Choice**: Measure request turnaround using Dart's `Stopwatch` and report duration in milliseconds.
- **Rationale**: Provides immediate insight into whether slow playback is due to network latency, large paragraph size, or provider response times.

## Risks / Trade-offs

- **[Risk]** Log buffer capacity saturation → **Mitigation**: `AiLogger` maintains a ring buffer capped at 200 entries, preventing memory leaks.
