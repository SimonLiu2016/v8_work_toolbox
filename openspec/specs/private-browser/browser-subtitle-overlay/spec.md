# private-browser/browser-subtitle-overlay Specification

## Purpose
Renders synchronized subtitle text as a native overlay above the WKWebView surface, tracking video playback progress via JS bridge.

## Requirements

### Requirement: JS bridge time sync
The system SHALL inject a WKUserScript that polls `video.currentTime` at approximately 250ms intervals when the video is playing, posting the current time to the native layer via a WKScriptMessageHandler named `subtitleTimeUpdate`. Polling SHALL pause when the video is paused or ended.

#### Scenario: Time updates posted during playback
- **WHEN** a video on the current page is playing and subtitle data is mounted
- **THEN** the injected JS posts the video's `currentTime` to the native handler at ~250ms intervals, and the native overlay updates to display the subtitle segment corresponding to the reported time

#### Scenario: Polling pauses on video pause
- **WHEN** the user pauses the video on the page
- **THEN** the injected JS stops posting time updates and the native overlay freezes on the last displayed subtitle segment until playback resumes

#### Scenario: Multiple video elements on page
- **WHEN** a page contains multiple `<video>` elements
- **THEN** the JS bridge tracks the video element most recently determined to be active (the one with the ongoing `play` event), and only that element's `currentTime` is posted

### Requirement: Subtitle overlay rendering
The system SHALL display a native NSView/CALayer overlay positioned above the WKWebView surface showing the subtitle segment matching the current playback time, styled with semi-transparent dark background and centered at the bottom of the video area.

#### Scenario: Correct segment displayed at current time
- **WHEN** the native layer receives a time update of T seconds
- **THEN** the overlay finds the subtitle segment where `start <= T < end` and displays its `text`; if no segment matches, the overlay shows no text (blank, but the view remains present)

#### Scenario: Segment transition
- **WHEN** the playback time advances past a segment's `end` value to the next segment's `start` value
- **THEN** the overlay updates the displayed text to the new segment's text with a brief cross-fade transition (≤ 100ms)

#### Scenario: Overlay styling
- **WHEN** a subtitle segment is displayed
- **THEN** the text is rendered in white with a semi-transparent dark rounded rectangle background, centered horizontally and positioned at the bottom 20% of the WKWebView's visible video area

### Requirement: Subtitle source mount
The overlay SHALL accept subtitle data — an array of `{start: Float, end: Float, text: String}` segments — pushed to it by the video-enhancer subtitle panel. Mounting new data replaces any previously loaded subtitle data.

#### Scenario: Mount subtitle data from Fast Extract
- **WHEN** the video-enhancer subtitle panel completes a Fast Extract and passes the parsed segment array to the overlay
- **THEN** the overlay stores the segments, enables time-based rendering, and displays the appropriate segment at the current playback time immediately

#### Scenario: Mount new subtitle data replaces previous
- **WHEN** the user triggers a second subtitle extraction while a subtitle track is already mounted
- **THEN** the overlay discards the previous segment array and replaces it with the new data, resuming synchronized display from the current playback time

#### Scenario: Mount with empty segment array
- **WHEN** an empty segment array is mounted (e.g. Fast Extract found no segments)
- **THEN** the overlay stores the empty array, displays no text, and remains in the disabled/blank state

### Requirement: Fullscreen follow
When the page's `<video>` element enters browser fullscreen via the Fullscreen API, the native subtitle overlay SHALL reposition and resize to cover the fullscreen surface, maintaining subtitle visibility.

#### Scenario: Video enters fullscreen
- **WHEN** the browser video enters fullscreen (via the Fullscreen API or a site's native fullscreen button)
- **THEN** the native overlay detects the WKWebView fullscreen window, repositions itself to cover the full screen, and continues rendering subtitles in sync

#### Scenario: Video exits fullscreen
- **WHEN** the user exits fullscreen (via Escape or the site's exit fullscreen control)
- **THEN** the overlay returns to its original position anchored to the WKWebView's in-page video area and continues rendering subtitles

### Requirement: Toggle visibility
Subtitle display SHALL be toggled on or off by the user. The overlay SHALL default to hidden on each new page load. Toggling is accessible from the video-enhancer toolbar's Subtitles button.

#### Scenario: Default off on page load
- **WHEN** a new page finishes loading in the browser
- **THEN** the subtitle overlay visibility is reset to hidden regardless of the previous page's subtitle state

#### Scenario: Toggle subtitle display on
- **WHEN** subtitle data is mounted and the user enables the subtitle display via the Subtitles toggle
- **THEN** the native overlay becomes visible and begins rendering subtitle segments in sync with playback

#### Scenario: Toggle subtitle display off
- **WHEN** subtitles are currently visible and the user toggles them off
- **THEN** the native overlay hides immediately; the subtitle data remains mounted so toggling on again resumes rendering without re-extraction
