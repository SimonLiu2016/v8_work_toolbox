# notebook-editor Delta

## ADDED Requirements

### Requirement: Asset affordance reflects persisted state
The asset/credential affordance in the note metadata bar SHALL display values that reflect
the persisted asset fields of the note, not a snapshot captured when the surface was opened.
After an asset field is saved, the affordance SHALL be refreshed from current persisted
state so a subsequently opened editing surface shows the value just written.

#### Scenario: Saved asset value is visible after reopening
- **WHEN** user sets an asset category and dates in the asset dialog, confirms, and then reopens the asset dialog
- **THEN** the dialog shows the values that were just saved
- **AND** the metadata-bar affordance reflects the same state (e.g. category or expiry countdown).

#### Scenario: Consecutive edits within one session stay consistent
- **WHEN** user saves an asset field and immediately saves another asset field in the same session
- **THEN** each save is applied on top of the latest persisted state
- **AND** no previously saved value is reverted by a stale in-memory copy.

#### Scenario: Editing surface reads current state on open
- **WHEN** the asset editing surface opens for a note whose asset fields were changed elsewhere (another window, or a prior dialog)
- **THEN** it reads the current persisted values rather than an earlier in-memory snapshot.
