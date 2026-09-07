# Tasks: Document & Web AI Audio Reader

## 1. Dependencies & Foundation

- [x] 1.1 Add audioplayers: ^6.0.0 dependency to pubspec.yaml and resolve dependencies
- [x] 1.2 Define reading document and chunk models (ReadingDocument, ReadingChunk, TtsVoiceOption)
- [x] 1.3 Implement audio cache directory manager (~/.v8worktoolbox/audio_cache/)

## 2. Multi-Format Document Ingestion Engine

- [x] 2.1 Implement TXT and Markdown file parser with formatting cleaning
- [x] 2.2 Implement Word (.docx) extractor via macOS textutil and XML archive fallback
- [x] 2.3 Implement PDF extractor using native macOS PDFKit integration
- [x] 2.4 Implement EPUB (.epub) parser extracting chapter manifests and XHTML streams
- [x] 2.5 Implement Web URL article extractor with HTML noise filtering and readability extraction
- [x] 2.6 Implement intelligent paragraph chunking and punctuation boundary splitter

## 3. Tri-Mode TTS Synthesis Pipeline

- [x] 3.1 Implement abstract TtsEngine interface and synthesis options
- [x] 3.2 Implement Edge-TTS free neural voice synthesizer (Xiaoxiao, Yunxi, etc.)
- [x] 3.3 Implement OpenAI-compatible (/v1/audio/speech) custom AI TTS provider
- [x] 3.4 Implement macOS native speech synthesizer (say / AVSpeechSynthesizer) offline fallback
- [x] 3.5 Implement TtsSynthesisCoordinator with sliding-window pre-fetching and queue control

## 4. Audio Playback & Synchronization

- [x] 4.1 Implement AudioReaderController managing AudioPlayer lifecycle and chunk sequencing
- [x] 4.2 Implement play/pause, seek, 0.5x~2.5x speed scaling, and seamless chunk transition
- [x] 4.3 Implement MP3 export service merging cached audio chunks into a standalone audio file

## 5. UI & Tool Registration

- [x] 5.1 Build DocAudioReaderPage with file drag-and-drop zone and URL input dialog
- [x] 5.2 Build reading text view with spotlight paragraph highlighting and click-to-jump
- [x] 5.3 Build persistent bottom audio control bar, volume/speed controls, and voice selector modal
- [x] 5.4 Register doc-audio-reader in lib/tools/registry.dart and update sidebar navigation
- [x] 5.5 Write comprehensive unit and widget tests for parser, chunking, and player controller
