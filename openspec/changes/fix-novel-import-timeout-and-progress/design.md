## Context

In `AiConstraintEngine.run`, the default timeout is `const Duration(seconds: 120)`. While sufficient for short prompts, `extractNovelMaster` and `segmentNovelEpisodes` involve thousands of tokens of input and massive JSON outputs, requiring 60-100s under normal load and >120s under peak load.

## Goals / Non-Goals

**Goals:**
- Increase timeout for `novelMasterExtraction` and `novelEpisodeSegmentation` to 240 seconds (`Duration(seconds: 240)`).
- Add an elapsed-seconds ticker in `IdeaIncubatorPanel` during novel file import.

**Non-Goals:**
- Changing chunking size for novel texts (>35,000 characters already gets truncated safely).

## Decisions

### Decision 1: Per-task timeout mapping in `AiConstraintEngine`
- Rather than increasing the timeout globally for all small tasks (which would make network failure detection sluggish), define a `defaultTimeoutFor(StudioAiTask task)` helper:
  - `StudioAiTask.novelMasterExtraction`: 240 seconds
  - `StudioAiTask.novelEpisodeSegmentation`: 240 seconds
  - Others: 120 seconds
- Callers may still override explicitly.

### Decision 2: Periodic Timer in `IdeaIncubatorPanel`
- Start a `Timer.periodic(const Duration(seconds: 1))` on import start, track `_elapsedSec`, and format into `_novelImportStatus`. Cancel timer in `finally`.
