# private-media-player Delta Specification
# Change: add-privacy-browser

## Purpose
Delta spec capturing additions to the `private-media-player` capability introduced by the `add-privacy-browser` change.

## ADDED Requirements

### Requirement: Extended browser-origin bookmark data model
The favorites system SHALL accept VideoBookmark entries originating from the private browser, which include additional fields: `source_url` (original web URL), `platform` (e.g. YouTube, MissAV), and `ai_summary`. These browser-origin entries SHALL be displayed alongside local file favorites, visually distinguished by a platform badge.

#### Scenario: Browser-origin bookmark appears in favorites list
- **WHEN** the user opens the private media player's Favorites view after having saved a video from the private browser
- **THEN** the browser-origin VideoBookmark appears in the list alongside local file favorites, displaying the cached thumbnail, title, platform badge (e.g. "YouTube", "MissAV"), and added_at timestamp

#### Scenario: Platform badge displayed on browser-origin entry
- **WHEN** a VideoBookmark with a non-nil `platform` field is rendered in the favorites list or detail view
- **THEN** a colored platform badge (using platform-specific branding color and abbreviated name) is overlaid on the thumbnail corner, distinguishing it from local file entries which have no badge

#### Scenario: Open browser-origin bookmark from favorites
- **WHEN** the user double-clicks or selects "Play" on a browser-origin VideoBookmark in the favorites list
- **THEN** the media player attempts to stream the `source_url` directly; if streaming fails or the URL is unavailable, the player presents an option to re-download via the browser's download queue

#### Scenario: AI summary visible in detail view
- **WHEN** the user opens the detail view of a browser-origin bookmark that has a non-empty `ai_summary` field
- **THEN** the `ai_summary` text is displayed in a dedicated "AI Summary" section within the detail panel, below the standard metadata fields

#### Scenario: Local file favorites unaffected
- **WHEN** the favorites list contains both local file entries and browser-origin VideoBookmark entries
- **THEN** local file favorites display without a platform badge and do not expose `source_url`, `platform`, or `ai_summary` fields; the two types coexist in the same list without layout or data conflicts
