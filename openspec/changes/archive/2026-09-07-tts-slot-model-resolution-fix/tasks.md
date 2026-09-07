## 1. Fix Model Resolution Logic

- [x] 1.1 Refactor model extraction in OpenAiTtsEngine to prioritize slot candidate models and provider model inspection
- [x] 1.2 Synchronize active slot model resolution in DocAudioReaderPage settings dialog

## 2. Verification & Re-deployment

- [x] 2.1 Add unit tests verifying slot model resolution when systemProviderId is set and provider.ttsModels is empty
- [x] 2.2 Rebuild and install fresh release binary to /Applications/V8WorkToolbox.app
