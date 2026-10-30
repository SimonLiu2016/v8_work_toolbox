## Purpose

Defines the system-level audio capture requirements for macOS live translation, including mandatory entitlements, Info.plist declarations, robust FFmpeg multi-channel downmixing, sensitive VAD energy thresholds, and live input level metrics.

## ADDED Requirements

### Requirement: macOS Audio Input Entitlement and Usage Description
The macOS application bundle and ad-hoc code signature SHALL declare the audio input entitlement `com.apple.security.device.audio-input` and the `NSMicrophoneUsageDescription` property in `Info.plist`. The local deployment script SHALL assert that `audio-input` is present in the final signature, preventing macOS TCC from silencing audio input streams.

#### Scenario: Running audio capture with valid entitlements
- **WHEN** the application starts FFmpeg to capture audio from a hardware microphone or virtual audio device (such as BlackHole 2ch)
- **THEN** macOS AVFoundation grants audio input stream access without silencing or filling the buffer with zero bytes.

#### Scenario: Local deployment assertion fails if entitlement missing
- **WHEN** the local deployment script runs code signature verification
- **THEN** it validates that `com.apple.security.device.audio-input` is present in the application's signature entitlements, failing the deployment step if missing.

### Requirement: Robust Multi-channel Downmix and FFmpeg Process Supervision
The audio capture service SHALL adaptively configure FFmpeg channel mapping for capture devices with more than 2 channels (such as 64-channel virtual devices or aggregate devices), injecting an explicit downmix filter (`-af "pan=mono|c0=0.5*c0+0.5*c1"`), and SHALL monitor the FFmpeg child process exit code, raising a descriptive error if the process terminates abnormally.

#### Scenario: Capturing audio from a multi-channel device
- **WHEN** the user selects a capture device with more than 2 channels (e.g. Soundflower 64ch or 65ch aggregate device)
- **THEN** FFmpeg is launched with an explicit pan filter to downmix the primary channels to mono without throwing rematrix parameter errors (code -22).

#### Scenario: Catching unexpected FFmpeg termination
- **WHEN** the FFmpeg capture process exits unexpectedly with a non-zero exit code
- **THEN** the audio capture service catches the termination, extracts the stderr error message, and transitions the coordinator state to error.

### Requirement: Sensitive and Configurable VAD Energy Threshold
The voice activity detection (VAD) chunker SHALL use a default energy threshold calibrated for normal system and web browser media volume (defaulting to 50.0 RMS or lower instead of 500.0 RMS), and SHALL broadcast real-time audio input level metrics (RMS) to the UI.

#### Scenario: Detecting speech at normal web media volume
- **WHEN** system audio or web video plays speech at typical moderate volume (e.g. 50-200 RMS)
- **THEN** the VAD chunker correctly identifies the speech frames and emits audio chunks for transcription instead of discarding them as silence.
