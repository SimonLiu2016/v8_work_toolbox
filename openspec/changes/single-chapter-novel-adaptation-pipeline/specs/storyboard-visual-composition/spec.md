## ADDED Requirements

### Requirement: Single-chapter novel adaptation pipeline
The system SHALL ingest full-text single chapter novel content without mechanical prefix truncation, pass the entire chapter narrative into the AI adaptation constraint engine, and produce a structured single-episode synopsis (300 to 500 Chinese characters) capturing opening hooks, conflict escalation, narrative climax, and ending suspense.

#### Scenario: Single chapter novel import without narrative truncation
- **WHEN** user selects a single-chapter novel text file (exceeding 500 characters) and confirms single-episode import
- **THEN** system analyzes the complete chapter text, preserves character conflict and dramatic climax, and saves an adapted single-episode synopsis into the target episode outline without truncating at 480 characters

#### Scenario: Storyboard breakdown receives full-chapter adapted synopsis
- **WHEN** user navigates to the storyboard board for an episode imported from a novel chapter and triggers AI storyboard breakdown
- **THEN** the breakdown engine reads the comprehensive chapter synopsis and generates 8 to 16 shots covering the entire progression from chapter opening to ending cliffhanger
