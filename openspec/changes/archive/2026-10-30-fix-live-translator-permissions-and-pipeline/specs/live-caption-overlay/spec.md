## Purpose

Specifies the user interface and presentation requirements for live subtitles, ensuring real-time captions and input audio levels are visible directly within the main tool window and error alerts are surfaced in both main and floating overlay views.

## ADDED Requirements

### Requirement: Main Window Embedded Caption Stream and VU Meter
The main `LiveTranslatorPage` SHALL embed an in-page live caption transcript view displaying real-time speech and translation segments, and a visual audio level meter (VU meter) reflecting current input RMS energy, ensuring the user can immediately verify audio capture and recognition without opening the floating window.

#### Scenario: Real-time caption update in main window
- **WHEN** audio chunks are transcribed by the coordinator while the main window is open
- **THEN** speech and translation segments are rendered directly in the main page's transcript card in real time.

#### Scenario: Visual input level verification
- **WHEN** audio is flowing through the selected capture device
- **THEN** the audio level meter in the main window animates in proportion to the RMS energy, providing immediate confirmation that sound is being received.

### Requirement: Cross-window Error Alert Propagation
When an ASR exception (such as HTTP 401 authentication failure, HTTP 402 quota exceeded, or capture process termination) occurs, the error message SHALL be propagated to both the main translator page and the active floating caption window, displaying an attention-grabbing alert banner or toast.

#### Scenario: Floating overlay displays error toast
- **WHEN** the coordinator encounters an ASR error while the floating overlay is visible
- **THEN** the floating window displays an error banner explaining the failure (e.g. quota exceeded or endpoint unreachable) instead of remaining blank.
