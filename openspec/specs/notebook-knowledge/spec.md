# notebook-knowledge Specification

## Purpose
Defines batch AI organization capabilities for the notebook knowledge graph, enabling bulk automated tag extraction, related note discovery, safe persistence, non-blocking progress monitoring, and dynamic graph synchronization.
## Requirements
### Requirement: Batch AI Organizer Trigger and Configuration Dialog
The knowledge graph view SHALL provide an entry button in its top header bar that opens a configuration dialog displaying notebook counts and allowing users to select the processing scope and organization tasks before running.

#### Scenario: User opens batch AI organizer dialog
- **WHEN** the user clicks the "批量AI整理" action button in the knowledge graph header
- **THEN** the system displays a modal configuration dialog presenting the total number of active notes, the count of unconnected notes, and scope options for "全部笔记" (all notes) and "仅未关联的孤立笔记" (unconnected notes only).

#### Scenario: User initiates batch organizer with selected scope
- **WHEN** the user selects a processing scope and clicks the "开始整理" button
- **THEN** the dialog closes and the system kicks off the batch organization queue using the selected scope.

#### Scenario: User cancels batch organizer before start
- **WHEN** the user clicks the "取消" button or dismisses the dialog
- **THEN** no background processing starts and the knowledge graph view remains in its idle state.

### Requirement: Embedded Non-Blocking Progress Indicator in Knowledge Graph Header
The knowledge graph header SHALL replace the idle toolbar with an embedded progress banner while batch organization is active, allowing continuous graph interaction without blocking modal overlays.

#### Scenario: Displaying real-time progress during batch processing
- **WHEN** the batch organizer is actively processing notes
- **THEN** the knowledge graph header displays a linear progress indicator, the current note sequence count (e.g., "18 / 62 篇"), the title of the currently analyzed note, and a visible "停止" cancel button.

#### Scenario: Aborting ongoing batch processing
- **WHEN** the user clicks the "停止" cancel button during batch execution
- **THEN** the scheduler ceases processing subsequent notes, preserves already persisted tags and links, and reverts the header back to the idle state.

### Requirement: Automated Safe Data Ingestion and Fault-Tolerant Scheduling
The batch organizer SHALL automatically persist AI-recommended tags and links into the local database with duplicate prevention, skip trivial notes, and tolerate single-note AI execution errors.

#### Scenario: Automatic tag ingestion and deduplication
- **WHEN** AI returns candidate tag suggestions for a note in the batch
- **THEN** the system creates missing tag entities, merges new tags with existing note tags, and persists the combined set without creating duplicate tag records.

#### Scenario: Automatic relation link creation without self-loops
- **WHEN** AI suggests related note connections with reasons
- **THEN** the system records each valid link in the note_links table while discarding self-links and duplicate edges.

#### Scenario: Skipping empty or extremely short notes
- **WHEN** a note in the queue has empty title and body or contains fewer than 5 non-whitespace characters
- **THEN** the batch processor increments the progress counter and immediately proceeds to the next note without invoking the AI model.

#### Scenario: Resilience against single note AI failures
- **WHEN** an AI chat API request times out or returns an error for a specific note
- **THEN** the batch processor logs the failure, marks the note as skipped or failed in progress statistics, and continues processing the remaining notes in the queue.

### Requirement: Post-Batch Summary and Graph Reload Trigger
Upon completion or user-initiated cancellation of the batch organizer, the system SHALL display a summary of changes and reload the knowledge graph.

#### Scenario: Automatic graph refresh and toast summary on completion
- **WHEN** all scheduled notes in the batch have been processed or when the user halts processing
- **THEN** the system presents a summary notification showing processed count, new tags added, and new links created, and automatically triggers a graph data reload and force-directed layout recalculation.

### Requirement: Asset note entries with structured fields
The notebook SHALL allow a note to carry optional structured asset fields (category, purchase date, service period, expiry date) in addition to its Delta rich-text content, so that durable consumer assets (extended warranties, subscriptions, insurance, memberships) can be recorded with machine-queryable dates. A note without asset fields remains a regular note with no overhead.

#### Scenario: Recording an asset note
- **WHEN** user marks a note as an asset entry and fills category, purchase date, and expiry date
- **THEN** the note is stored with those fields populated, and the note list displays an asset badge with a countdown to expiry

#### Scenario: Regular note unaffected
- **WHEN** user creates or edits a note without touching asset fields
- **THEN** the note stores empty asset fields, behaves identically to before, and incurs no extra prompts or badges

#### Scenario: Attaching a credential file to an asset
- **WHEN** user attaches a screenshot or receipt to an asset note and marks it as a credential
- **THEN** the attachment is associated with the asset entry and retrievable as the credential of record for that asset

### Requirement: Expiry reminders for asset notes
The system SHALL scan asset notes for upcoming expiry dates and notify the user in advance, so that a service purchased years ago is not forgotten when the covered item fails.

#### Scenario: Reminder before expiry
- **WHEN** an asset note's expiry date is within a configurable lead window (default 30 days) and the asset is not yet expired
- **THEN** the system sends a macOS notification naming the asset, the expiry date, and the credential location, and surfaces the asset in an in-app reminders list

#### Scenario: Past-due asset
- **WHEN** an asset's expiry date has passed
- **THEN** the system marks the asset as expired in the list and stops issuing reminders, without deleting the note

#### Scenario: Reminder respects user dismissal
- **WHEN** user dismisses a reminder for a given asset
- **THEN** the system does not re-notify for the same expiry within a cooldown, while still listing the asset as due-soon

### Requirement: RAG question-answering over the notebook
The notebook SHALL provide an in-notebook AI question-answering panel that retrieves relevant note fragments via full-text search, feeds them as context to the AI, and returns an answer with citations linking back to the source notes.

#### Scenario: Asking a question about stored knowledge
- **WHEN** user asks a natural-language question in the notebook QA panel (e.g. "the soy milk maker broke, what can I do")
- **THEN** the system runs FTS over note titles and contents, selects the top matching fragments, asks the AI to answer grounded in those fragments, and displays the answer with clickable citations to each source note

#### Scenario: Question with no matching notes
- **WHEN** user asks a question and FTS returns no matching notes
- **THEN** the system tells the user it has no relevant notes rather than fabricating an answer, and MAY offer to fall back to web search

#### Scenario: Answer cites the credential
- **WHEN** the retrieved context includes an asset note with a credential attachment
- **THEN** the answer references the credential attachment and its note, so the user can locate the proof of purchase

### Requirement: AI-assisted note tagging
The system SHALL offer AI-suggested tags for regular notes, proposed by the AI based on note content, which the user confirms before they are applied.

#### Scenario: Suggesting tags for a note
- **WHEN** user requests AI tag suggestions for a note
- **THEN** the AI proposes a set of candidate tags based on the note's content and existing tag vocabulary, and presents them for user approval

#### Scenario: User confirms or rejects suggestions
- **WHEN** user accepts some and rejects other suggested tags
- **THEN** only the accepted tags are written to the note; rejected ones are discarded and not silently stored

#### Scenario: Suggestion respects existing tags
- **WHEN** the note already has tags
- **THEN** the AI does not duplicate existing tags and MAY propose refinements or removals, but never removes a tag without explicit user action

### Requirement: AI-assisted note linking
The system SHALL offer AI-suggested links between notes (a generalized `related_to` relation with a free-text reason), which the user confirms before they are written to the graph.

#### Scenario: Suggesting links for a note
- **WHEN** user requests AI link suggestions for a note
- **THEN** the AI proposes candidate related notes from the user's library with a short reason for each, and presents them for user approval

#### Scenario: User confirms or rejects links
- **WHEN** user accepts some and rejects other suggested links
- **THEN** only the accepted links are written to the note_links table; rejected ones are discarded

#### Scenario: AI never silently modifies the graph
- **WHEN** the AI suggests tags or links
- **THEN** no tag or link is persisted without an explicit user confirmation action

### Requirement: Generalized note relationship graph
The notebook SHALL store note-to-note relationships in a `note_links` table as a generalized `related_to` relation with an optional free-text reason, without predefined relationship types, so that AI-assisted and user-authored links share one uniform schema.

#### Scenario: Creating a link between two notes
- **WHEN** user or confirmed AI suggestion links note A to note B with a reason
- **THEN** a row is written to note_links recording source note, target note, the relation, and the reason, and the link appears in both notes' detail views

#### Scenario: Bidirectional visibility of links
- **WHEN** a link exists from note A to note B
- **THEN** both note A and note B display the relationship in their detail views, regardless of which was the source

#### Scenario: Deleting a note cascades its links
- **WHEN** a note is permanently deleted
- **THEN** all note_links rows referencing it (as source or target) are removed

### Requirement: Knowledge graph view and multi-hop traversal
The notebook SHALL provide a graph view rendering notes as nodes and note_links as edges, and SHALL support multi-hop traversal queries so the AI and the user can follow chains of relationships.

#### Scenario: Opening the graph view
- **WHEN** user opens the knowledge graph view
- **THEN** notes render as nodes and links as edges, with the currently selected note highlighted and its neighborhood emphasized

#### Scenario: Multi-hop traversal for a question
- **WHEN** the AI answers a question by traversing the graph (e.g. asset → related product → related merchant)
- **THEN** the answer traces the path of notes it followed, and the user can inspect each hop

