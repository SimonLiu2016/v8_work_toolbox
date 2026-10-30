# notebook-editor Delta

## ADDED Requirements

### Requirement: Asset fields panel
The editor SHALL provide a panel for editing a note's optional asset fields (category, purchase date, service period, expiry date) and for flagging an attachment as a credential, alongside the rich-text editor. The panel is collapsible and hidden by default for notes that carry no asset data.

#### Scenario: Filling asset fields
- **WHEN** user opens the asset panel for a note and fills category, purchase date, and expiry date
- **THEN** the values are saved to the note's asset fields, and an asset badge with expiry countdown appears on the note in the list.

#### Scenario: Panel hidden for plain notes
- **WHEN** a note has no asset fields filled
- **THEN** the asset panel is collapsed and does not intrude on the editing surface.

#### Scenario: Flagging a credential attachment
- **WHEN** user selects an attachment in the asset panel and marks it as a credential
- **THEN** the attachment is flagged as the credential of record, and is surfaced in AI answers about that asset.

### Requirement: Related notes view in note detail
The editor's note detail view SHALL display the notes related to the current note via the `note_links` table, showing the related note's title and the link's free-text reason, with a click action that navigates to the related note.

#### Scenario: Viewing related notes
- **WHEN** user opens a note that has links to other notes
- **THEN** the detail view lists each related note with its title and the link reason, and clicking one navigates to that note.

#### Scenario: No related notes
- **WHEN** a note has no links
- **THEN** the related-notes section is absent or empty, without placeholder clutter.
