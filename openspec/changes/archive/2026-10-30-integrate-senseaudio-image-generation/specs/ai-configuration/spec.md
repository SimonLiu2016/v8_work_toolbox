## ADDED Requirements

### Requirement: Unified Multi-modal Provider and SenseAudio Image Protocol Adapter
The system SHALL support configuring SenseAudio as a unified multi-modal provider whose credentials and base URL are shared across both video and image capability slots. When generating images using SenseAudio, the system SHALL adhere to the official SenseAudio image generation protocol (supporting `POST /v1/image/sync` and `POST /v1/image/async` with `GET /v1/image/pending`), perform automatic resolution snapping to legal whitelist dimensions, support base64 Data URI reference images, and record all interactions to `AiLogger`.

#### Scenario: Unified provider credential and model sharing
- **WHEN** user configures the SenseAudio provider in the AI infrastructure settings
- **THEN** the single provider record holds video models (e.g. `doubao-seedance-2-0-260128`) and image models (e.g. `senseaudio-image-2.0-260319`), and the same API Key is shared across video and image generation without redundant credential entries

#### Scenario: Synchronous image generation via SenseAudio protocol
- **WHEN** an image generation request is dispatched to SenseAudio in synchronous mode
- **THEN** the system issues a `POST` request to `/v1/image/sync` with authorization headers, extracts the direct `url` field from the root JSON response, downloads the image file, and logs request/response details to `AiLogger`

#### Scenario: Asynchronous fallback and pending polling
- **WHEN** synchronous image generation is unavailable or timed out, or asynchronous mode is explicitly dispatched
- **THEN** the system issues a `POST` request to `/v1/image/async` to obtain a `task_id`, periodically queries `/v1/image/pending?task_id={task_id}` until the status is `completed`, and saves the resulting image to disk

#### Scenario: Automatic resolution snapping to supported dimensions
- **WHEN** a client requests an arbitrary portrait or landscape aspect ratio (such as 1080x1920 for vertical short videos)
- **THEN** the system automatically snaps the requested size to the nearest supported dimension whitelist for the chosen model (e.g. `1152x2048` or `864x1536` for `senseaudio-image-2.0-260319`), preventing `400000` parameter errors from the provider

#### Scenario: Transmitting reference image via Data URI
- **WHEN** a storyboard shot provides a character or scene reference image file
- **THEN** the system encodes the image to a base64 Data URI (`data:image/png;base64,...`) and includes it in the `reference` parameter of the SenseAudio request body
