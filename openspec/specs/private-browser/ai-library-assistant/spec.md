# private-browser/ai-library-assistant Specification

## Purpose
AI-powered layer for the video library providing automatic and manual smart tagging, natural-language semantic search, and a conversational AI panel for library management and video inquiry.

## Requirements

### Requirement: Auto smart tagging on favorite
When a VideoBookmark is created, the system SHALL automatically send the bookmark's title, page description (og:description if available), and platform to the global text LLM slot to generate suggested tags and a recommended category. Results SHALL be applied to the bookmark silently, or if user confirmation is preferred, surfaced as a brief confirm toast. The ai_tags[] and ai_summary fields SHALL be populated with the LLM response.

#### Scenario: Auto tagging on bookmark creation
- **WHEN** a new VideoBookmark is saved via the Favorite action
- **THEN** the system asynchronously sends `{title, description, platform}` to the text LLM, receives a list of suggested tags and a recommended category, and silently populates `ai_tags[]` and `ai_summary` on the bookmark record

#### Scenario: Suggested category auto-applied
- **WHEN** the LLM response includes a recommended category name that matches an existing category in the user's tree
- **THEN** the bookmark's `category_id` is set to that existing category; if no match is found, the bookmark remains uncategorized and the suggested name is shown in a confirm toast

#### Scenario: LLM unavailable during auto tagging
- **WHEN** the global text LLM slot is unavailable or returns an error during auto tagging
- **THEN** the bookmark is saved without `ai_tags[]` or `ai_summary`, and a non-blocking indicator is shown on the bookmark that AI analysis is pending, retryable from the detail view

### Requirement: Manual re-analysis
The user SHALL be able to trigger AI tag re-analysis on any existing bookmark from its detail view. The re-analysis SHALL replace the current `ai_tags[]` and update the `ai_summary` field.

#### Scenario: Trigger re-analysis from detail view
- **WHEN** the user clicks "Re-analyze with AI" in a bookmark's detail view
- **THEN** the system sends the bookmark's current `{title, notes, platform}` to the text LLM and displays a loading indicator on the ai_tags and ai_summary fields

#### Scenario: Re-analysis results applied
- **WHEN** the LLM returns a re-analysis response
- **THEN** the bookmark's `ai_tags[]` array is replaced with the new suggested tags and `ai_summary` is updated; the detail view refreshes to show the new values

#### Scenario: Re-analysis on a bookmark with edited notes
- **WHEN** the user has edited the `notes` field on a bookmark before triggering re-analysis
- **THEN** the updated notes content is included in the LLM prompt, allowing the AI to incorporate the user's own annotations into the generated summary and tags

### Requirement: Semantic search
The library search bar SHALL accept natural-language queries. When a query is detected as natural language (rather than a simple keyword), the system SHALL send the query to the global text LLM to produce a ranked list of matching bookmark IDs using locally stored metadata.

#### Scenario: Natural-language query matched against metadata
- **WHEN** the user types a natural-language query such as "有中文字幕的无码" in the library search bar
- **THEN** the system submits the query along with the local metadata corpus (titles, notes, ai_tags, ai_summary) to the LLM, and the returned ranked bookmark IDs are displayed as the search results list

#### Scenario: Semantic search result ranking
- **WHEN** the LLM returns ranked results for a natural-language query
- **THEN** bookmarks are displayed in the returned rank order, with a "Semantic Match" badge distinguishing them from keyword-match results

#### Scenario: Semantic search fallback to keyword
- **WHEN** the query is a single short word or appears to be a plain keyword (no semantic complexity)
- **THEN** the system falls back to the standard full-text keyword search on title and notes without invoking the LLM

#### Scenario: LLM unavailable during semantic search
- **WHEN** the global text LLM slot is unavailable when the user submits a semantic search query
- **THEN** the system falls back to keyword search and shows a brief notice that semantic search is temporarily unavailable

### Requirement: AI chat panel
A floating AI chat panel SHALL be accessible from the library toolbar, allowing the user to converse with the AI about their library contents and about the current browser page's video. The panel maintains conversation context for the duration of the session.

#### Scenario: Open AI chat panel
- **WHEN** the user clicks the AI Chat button in the library toolbar
- **THEN** a floating panel appears showing a conversation history area and a text input field; the panel is draggable and can be resized

#### Scenario: Library management conversation
- **WHEN** the user sends a message such as "帮我整理分类" (help me reorganize categories)
- **THEN** the system sends the message along with the user's current category tree structure and a sample of bookmark metadata to the LLM, and the LLM responds with suggested reorganization actions or questions; the user can apply suggestions via follow-up commands

#### Scenario: Library inquiry conversation
- **WHEN** the user asks "最近收藏了哪些xxx的视频" (which xxx videos have I recently favorited)
- **THEN** the system queries the local bookmark store for recently added bookmarks matching the topic, passes the results as context to the LLM, and the LLM formulates a conversational reply listing the relevant bookmarks

#### Scenario: Current page video inquiry
- **WHEN** the user asks about the video on the current browser page (e.g. "这个视频的女演员是谁")
- **THEN** the system includes the current page's title, URL, platform, and any available og:description as context in the LLM prompt, and the LLM responds based on that metadata without accessing video frames or audio

### Requirement: Privacy constraint on AI analysis
All AI analysis in the library assistant SHALL use only locally stored metadata (title, description, ai_tags, notes, ai_summary). No video frames, audio streams, or binary media content SHALL be sent to the AI for library assistant queries.

#### Scenario: AI analysis uses only text metadata
- **WHEN** any AI library assistant operation is executed (auto tagging, re-analysis, semantic search, or chat)
- **THEN** the data submitted to the LLM contains only string fields from the local database; no file paths, image data, audio data, or video frame data are included in the request payload

#### Scenario: AI chat panel cannot access raw video
- **WHEN** the user asks the AI chat panel a question about a video
- **THEN** the system provides only the textual metadata of the relevant bookmark or current page to the LLM, and if the LLM cannot answer from metadata alone, it responds indicating it does not have access to the video content
