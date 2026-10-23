## MODIFIED Requirements

### Requirement: Agnes video generation payload contract
The video generation adapter for Agnes AI SHALL compose video generation requests with valid payload fields (`model`, `prompt`, `mode`, `seconds`, `size`, `aspect_ratio`), and SHALL strictly conform to Agnes official mode mutual-exclusion rules: in keyframe mode, reference media fields (`images`, `audios`, `videos`) SHALL NOT be included; in reference mode, `first_frame` and `last_frame` SHALL NOT be included; in text mode, no media field SHALL be included. The adapter SHALL support `last_frame` alongside `first_frame`, and SHALL accept either one alone or both together in keyframe mode. The `size` value SHALL come from the model's supported resolution tiers and the `aspect_ratio` value SHALL come from the supported ratio whitelist; values outside either set SHALL NOT be submitted.

The maximum number of reference images accepted in reference mode SHALL come from the selected model's capability declaration, SHALL NOT be a hardcoded constant. When the caller supplies more reference images than the declared maximum, the adapter SHALL reject the request and surface the declared maximum to the caller, SHALL NOT silently truncate the list.

The declared maximum SHALL be adjustable by the user in settings, so that a supplier changing the limit does not require an application update. A model that declares no confirmed maximum SHALL express that as "no confirmed limit" rather than as a fabricated number.

The adapter SHALL accept audio reference media in reference mode and SHALL place them in the reference media array alongside images. Audio references SHALL be identified by index in the prompt using the same numbering scheme as image references. When no audio reference is supplied, the adapter SHALL NOT submit any audio field.

#### Scenario: Submitting video generation task for Agnes model
- **WHEN** user clicks generate video clip for a shot with keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing valid `model`, `prompt`, `mode`, `seconds`, `size`, `aspect_ratio`, `first_frame`, `image`, and `image_url`, and receives successful task dispatch

#### Scenario: Submitting video generation task without keyframe
- **WHEN** user triggers video generation for a shot that has no keyframe image
- **THEN** adapter automatically selects text mode, omits `first_frame`, and submits the prompt to Agnes video model

#### Scenario: Submitting video generation task for Agnes model in keyframe mode
- **WHEN** user triggers video generation with a keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing `model`, `prompt`, `mode: "keyframe"`, `seconds`, `size`, `aspect_ratio`, and `first_frame`, strictly excluding `images`, `audios`, or `videos`, and receives successful task dispatch

#### Scenario: Submitting video generation task for Agnes model with redundant frame bindings
- **WHEN** user triggers video generation with a keyframe image using Agnes video engine
- **THEN** adapter submits JSON payload containing valid `model`, `prompt`, `mode`, `seconds`, `size`, `aspect_ratio`, and `first_frame`, and receives successful task dispatch

#### Scenario: Submitting with both first and last frames
- **WHEN** user triggers video generation with both a first-frame and a last-frame image
- **THEN** adapter submits payload containing both `first_frame` and `last_frame` in keyframe mode, and does not require the first frame to be present when only a last frame is supplied

#### Scenario: Submitting with reference images only
- **WHEN** user triggers video generation with reference images but no first or last frame
- **THEN** adapter selects reference mode, submits the images in the reference media array, and omits `first_frame` and `last_frame`

#### Scenario: Submitting without any media
- **WHEN** user triggers video generation with only a prompt and no media input
- **THEN** adapter automatically selects text mode, omits all media fields, and submits the prompt to Agnes video model

#### Scenario: Reference image count exceeds declared maximum
- **WHEN** user triggers reference-mode generation with more reference images than the selected model's declared maximum
- **THEN** the adapter SHALL reject the request with an error naming the declared maximum and the supplied count
- **AND** the adapter SHALL NOT submit a silently truncated image list

#### Scenario: Declared maximum adjusted in settings
- **WHEN** the user changes a model's declared reference-image maximum in settings
- **THEN** the adapter SHALL enforce the new value on subsequent submissions
- **AND** the shot card warning SHALL use the new value

#### Scenario: No audio reference supplied
- **WHEN** user triggers reference-mode generation without supplying any audio reference
- **THEN** the submitted payload SHALL NOT contain any audio reference field
- **AND** the prompt SHALL NOT contain any audio reference index

#### Scenario: Audio reference supplied with matching index
- **WHEN** user triggers reference-mode generation supplying one audio reference
- **THEN** the payload SHALL carry the audio reference in the reference media array
- **AND** the prompt's audio reference index SHALL match the position of that audio in the submitted media array

#### Scenario: Requested resolution tier outside model support
- **WHEN** user requests a resolution tier that the selected model does not support (for example `1080P` on the Flash variant)
- **THEN** the adapter submits a tier the model supports, records the snap in the AI log, and does not submit a value outside the model's declared set

#### Scenario: Requested duration exceeds declared maximum
- **WHEN** user requests a 15-second Agnes clip and the declared model supports at most 12 seconds
- **THEN** the adapter submits `seconds` of 12, records the snap in the AI log, and does not submit a value outside the declared set

#### Scenario: Handling transient upstream rate limits (HTTP 429)
- **WHEN** Agnes video gateway returns HTTP 429 indicating upstream overload
- **THEN** adapter automatically retries up to 4 times with exponential backoff delay, reporting retry progress, before failing the task
