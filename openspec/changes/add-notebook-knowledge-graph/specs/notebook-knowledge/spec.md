# notebook-knowledge Delta

## Purpose

Provides a knowledge-base and AI integration layer over the notebook tool: structured asset/credential entries with expiry reminders, RAG question-answering over the user's notes, AI-assisted tagging and linking, and a generalized note-to-note relationship graph for multi-hop reasoning and visualization.

## ADDED Requirements

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
