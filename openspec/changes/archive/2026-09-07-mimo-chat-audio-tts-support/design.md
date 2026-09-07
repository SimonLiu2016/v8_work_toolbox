## Context

See `proposal.md` for motivation.

The `OpenAiTtsEngine` currently forces a `/audio/speech` endpoint and assumes an OpenAI legacy speech payload structure:
```json
{ "model": "tts-1", "input": text, "voice": "alloy" }
```
However, modern multi-modal and speech synthesis models like Xiaomi MiMo (`mimo-v2.5-tts`) implement the OpenAI Chat Audio Completions protocol (`POST /v1/chat/completions`) with the synthesis text wrapped in an assistant message and audio format specified in the `audio` block:
```json
{
  "model": "mimo-v2.5-tts",
  "messages": [{"role": "assistant", "content": text}],
  "audio": {"format": "wav", "voice": "mimo_default"}
}
```
The response returns a Base64-encoded audio payload in `choices[0].message.audio.data`.

## Goals / Non-Goals

**Goals:**
- Dynamically detect when a TTS target is a Chat Audio Completions model (Xiaomi MiMo or GPT-4o Audio) versus a legacy Speech model (`tts-1`), routing to the right endpoint and payload structure.
- Add preset definitions for Xiaomi MiMo's 8 official voices (`mimo_default`, `冰糖`, `茉莉`, `苏打`, `白桦`, `Mia`, `Chloe`, `Milo`, `Dean`) and provide automatic fallback to `mimo_default` if an incompatible voice ID is passed.
- Enable `AudioCacheManager` to detect audio container format by magic byte inspection (`RIFF/WAVE` vs `ID3/MPEG`) and cache with the appropriate extension (`.wav` or `.mp3`) to ensure macOS `AVPlayer` compatibility.
- Surface TTS synthesis error messages directly in the reader UI via Toast/SnackBar notifications instead of silent buffering cancellation.

**Non-Goals:**
- Modifying streaming WebSocket protocols for real-time PCM (chunk-based synthesis fits document reading and caching perfectly).
- Changing AI configuration store schema or key storage.

## Decisions

### Decision 1: Protocol Discrimination in `OpenAiTtsEngine`
- **Choice**: Check if the model or endpoint matches Chat Audio conventions (e.g. `model.startsWith('mimo-')`, `baseUrl.contains('xiaomimimo.com')`, or `model.contains('audio')`).
- **Rationale**: Keeps full backward compatibility with OpenAI `tts-1`, SiliconFlow, Groq, and standard `/v1/audio/speech` endpoints, while unlocking MiMo and newer chat-audio models seamlessly.
- **Alternatives Considered**: Creating a completely separate engine class (`MiMoTtsEngine`). Rejected because MiMo explicitly adheres to the OpenAI Chat Completions API format, and users configure it under OpenAI/System AI provider slots.

### Decision 2: MiMo Voice Presets and Defensive Fallback
- **Choice**: Define an explicit list of MiMo voice presets. If the target is MiMo and the configured voice is not one of the supported names, substitute `mimo_default`.
- **Rationale**: Prevents unexpected HTTP 400 errors when users switch to "跟随系统AI配置" while retaining their previous Edge-TTS or OpenAI voice setting.

### Decision 3: Audio Cache Format Detection
- **Choice**: Inspect the first 12 bytes of synthesized audio bytes:
  - If bytes start with `RIFF` and contain `WAVE`, file extension is `.wav`.
  - Otherwise, default to `.mp3`.
- **Rationale**: macOS `AVPlayer` strictly relies on file extension when playing local file URLs. Using `.wav` for WAV files and `.mp3` for MP3 files eliminates format parse errors.

### Decision 4: Observable Error Reporting to Controller & UI
- **Choice**: Add an error listener / notification in `AudioReaderController` and pass synthesis failure messages to the UI.
- **Rationale**: Allows users to immediately see if an API key is invalid, quota exceeded, or network timed out, eliminating "silent failure" confusion.

## Risks / Trade-offs

- **[Risk]** Base URL path formatting (`/v1` duplicate or omitted) → **Mitigation**: Normalize baseUrl cleanly before appending `/v1/chat/completions` or `/v1/audio/speech`.
- **[Risk]** WAV file sizes larger than MP3 → **Mitigation**: Each chunk is typically 1-3 sentences (under 100-300KB), which writes in under 5ms on modern SSDs and consumes minimal disk space.
