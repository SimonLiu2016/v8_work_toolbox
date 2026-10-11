## MODIFIED Requirements

### Requirement: Cross-format local and online media playback
The system SHALL play local media files and parsed online streams across popular formats (.mp4, .mkv, .mov, .webm, .flv, .ts, .mp3, .wav, .m4a) with hardware acceleration, and MUST ensure native player runtime initialization is globally accessible across both the primary window and spawned desktop sub-windows.

#### Scenario: Open local media file
- **WHEN** user selects or drops a local audio/video file into the player
- **THEN** player loads the media stream, displays video surface (for video) or audio waveform cover (for audio), and starts playback

#### Scenario: Stream parsed online video
- **WHEN** user initiates playback of a parsed online video URL
- **THEN** player streams the media using appropriate network headers without requiring full file download

#### Scenario: Sub-window media playback initialization
- **WHEN** user launches or navigates within an independent sub-window (such as AI Video Studio) and initiates video playback
- **THEN** the media player runtime (MediaKit) is pre-initialized, successfully allocating hardware-accelerated video rendering textures without crashing or displaying an uninitialized blank grey canvas

## ADDED Requirements

### Requirement: Image cache eviction upon frame regeneration
The system SHALL evict stale image cache entries when a storyboard frame image is regenerated or overwritten on disk, ensuring immediate visual update in the user interface.

#### Scenario: Keyframe regeneration cache invalidation
- **WHEN** an AI generation task successfully overwrites a shot frame image file (e.g. `shot_1.png`)
- **THEN** system automatically evicts the corresponding file image from Flutter's memory image cache and updates the storyboard thumbnail without requiring an application or window restart
