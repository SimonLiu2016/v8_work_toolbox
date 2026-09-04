## Purpose

Provides privacy-preserving metadata analysis and AI-driven risk assessment for ambiguous disk directories and unknown files.

## ADDED Requirements

### Requirement: Batch diagnostics for low-confidence items
The system SHALL automatically collect metadata (path patterns, file extensions, size, folder depth, access timestamps) for low-confidence unknown directories and batch-query `AiService` for safety categorization.

#### Scenario: Automatic batch diagnostic recommendation
- **WHEN** scan identifies ambiguous directories without recognized bundle associations
- **THEN** the system batches them into a single diagnostic request and tags each item with an AI safety rating (Safe, Caution, Danger) and deletion advice.

### Requirement: On-demand single item AI analysis
The user interface SHALL provide a dedicated AI inspection button on any file or directory item, allowing interactive explanation of the item's purpose and deletion consequences.

#### Scenario: User queries unknown item
- **WHEN** user clicks "Ask AI" on a specific candidate item
- **THEN** a detailed analysis sheet displays inferred source application, risk evaluation, and human-readable recommendation without transmitting file contents.
