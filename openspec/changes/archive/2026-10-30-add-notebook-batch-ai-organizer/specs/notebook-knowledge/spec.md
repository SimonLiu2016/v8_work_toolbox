## Purpose

Defines batch AI organization capabilities for the notebook knowledge graph, enabling bulk automated tag extraction, related note discovery, safe persistence, non-blocking progress monitoring, and dynamic graph synchronization.

## ADDED Requirements

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
