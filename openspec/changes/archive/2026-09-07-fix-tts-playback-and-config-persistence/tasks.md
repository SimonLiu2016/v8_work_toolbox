## 1. Config Persistence and Smart Defaulting

- [x] 1.1 Create `ReaderConfigStore` to load and save `TtsSynthesisConfig` to `~/Library/Application Support/V8WorkToolbox/config/reader_config.json`
- [x] 1.2 Implement smart default resolution: if no config exists, inspect `AiConfigStore` for configured TTS model/provider and default to `TtsMode.customAi`
- [x] 1.3 Wire `ReaderConfigStore` into `DocAudioReaderPage` so configurations persist on change and reload upon page opening

## 2. Prefetch Queue Serialization & Concurrency Safety

- [x] 2.1 Remove eager prefetch `coordinator.ensureAhead` inside `AudioReaderController.loadDocument`
- [x] 2.2 In `AudioReaderController._playChunk`, ensure chunk `index` synthesis has absolute priority and only dispatch prefetch for chunk `index + 1` after active playback starts
- [x] 2.3 Verify `TtsSynthesisCoordinator` sequential queue locks to guarantee single-flight synthesis for commercial AI engines

## 3. Rate Limit (429) Stepped Backoff & Extended Timeout

- [x] 3.1 Increase `OpenAiTtsEngine` HTTP timeout to 90 seconds for long paragraph audio synthesis
- [x] 3.2 Update `OpenAiTtsEngine` HTTP 429 retry backoff with stepped intervals (4s, 10s, 20s) and emit descriptive warning logs
- [x] 3.3 Add visual UI status notification in `DocAudioReaderPage` when generating long audio chunks or waiting for rate limit backoff

## 4. Persistent File-Based Diagnostic Logging

- [x] 4.1 Update `AiLogger` to mirror formatted log entries asynchronously to `~/Library/Application Support/V8WorkToolbox/logs/ai.log` with automatic log size rotation
- [x] 4.2 Verify log persistence by running test logging and checking output file existence and format

## 5. Verification & End-to-End Testing

- [x] 5.1 Run unit and integration tests across reader models, config persistence, and controller scheduling
- [x] 5.2 Validate playback initiation with Xiaomi MiMo model and verify zero concurrency collisions and successful audio output
