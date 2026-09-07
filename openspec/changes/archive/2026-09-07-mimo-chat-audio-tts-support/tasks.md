## 1. Engine Protocol & Voice Adaptation

- [x] 1.1 Add MiMo voice definitions and safety fallback map to reader_models.dart
- [x] 1.2 Implement Chat Audio Completions request builder and Base64 audio response parser in OpenAiTtsEngine
- [x] 1.3 Add automatic protocol routing (/v1/chat/completions vs /v1/audio/speech) and voice fallback in OpenAiTtsEngine

## 2. Audio Cache & Playback Robustness

- [x] 2.1 Update AudioCacheManager to inspect magic bytes and persist files with correct .wav / .mp3 extension
- [x] 2.2 Update AudioReaderController to capture synthesis errors and notify listeners/UI

## 3. UI Voice Selection & Error Feedback

- [x] 3.1 Update doc_audio_reader_page.dart voice selector dropdown to display MiMo official voices when MiMo is active
- [x] 3.2 Add visible SnackBar error presentation in doc_audio_reader_page.dart when chunk synthesis fails

## 4. Verification & Testing

- [x] 4.1 Create automated unit tests for Chat Audio parsing, MiMo voice fallback, and cache format detection
- [x] 4.2 Run test suite to ensure all tests pass cleanly
