# notebook-editor Delta

## MODIFIED Requirements

### Requirement: Editor chrome theme isolation and full-width alignment
The system SHALL isolate **every light-surface panel in the notebook** from the global dark input decoration theme — including the note editor, the title input, the "问我的笔记" (ask-my-notes) panel, and the asset/credential dialog — and stretch the formatting toolbar across the full width of the editor container. Isolation SHALL be applied at the panel boundary (a light `Theme` wrapper overriding `filled: false` and a transparent fill), not patched field-by-field, so that newly added fields are covered by construction.

#### Scenario: Note title input background
- **WHEN** viewing or editing the note title
- **THEN** the title input field renders with transparent background on white canvas, with no dark gray box artifacts.

#### Scenario: Ask-my-notes panel input legibility
- **WHEN** the user opens the "问我的笔记" panel and types a question
- **THEN** the input field renders on the panel's light background with the global dark fill color suppressed
- **AND** the entered text is legible against that background.

#### Scenario: Asset dialog field legibility
- **WHEN** the user opens the asset/credential dialog and edits the category field
- **THEN** the field renders with the global dark fill color suppressed and its text legible.

#### Scenario: Newly added light-surface panel inherits isolation
- **WHEN** a new light-surface panel is added to the notebook UI
- **THEN** it is wrapped in the shared light-theme boundary rather than relying on each form field to override the global fill
- **AND** its form fields are legible without per-field fixes.

#### Scenario: Formatting toolbar width alignment
- **WHEN** viewing the note editor in any desktop window size
- **THEN** the formatting toolbar stretches to 100% width of the editor panel, aligning flush with the document canvas edges.

## ADDED Requirements

### Requirement: Note detail properties consolidated into the metadata bar
The note detail view SHALL present all of a note's property affordances — notebook selector, tags, asset/credential entry, AI tidy-up entry, and related-notes entry — together in the single metadata bar above the formatting toolbar. Property affordances MUST NOT be rendered as separate blocks below the toolbar, so that the editor canvas is not vertically compressed by property UI and a note's attributes are not split across two regions.

#### Scenario: Metadata bar holds all property affordances
- **WHEN** viewing a note in the detail view
- **THEN** the metadata bar contains the notebook selector, the tag list with an add-tag affordance, an asset/credential affordance, and an AI tidy-up affordance
- **AND** no asset panel, tidy-up button, or related-notes block is rendered between the formatting toolbar and the editor canvas.

#### Scenario: Asset affordance opens the full editor
- **WHEN** user activates the asset affordance in the metadata bar
- **THEN** a dialog opens carrying the full asset editing surface (category, purchase date, service period, expiry date, and credential flagging)
- **AND** saving it updates the note and closes the dialog.

#### Scenario: Asset affordance reflects asset state
- **WHEN** a note carries asset data
- **THEN** the asset affordance in the metadata bar reflects that state (e.g. shows the category or the expiry countdown)
- **AND** a note with no asset data shows the bare affordance without a misleading badge.

#### Scenario: Related-notes affordance appears only when links exist
- **WHEN** a note has one or more links
- **THEN** the metadata bar shows a related-notes affordance with the count, and activating it lists the related notes for navigation or removal
- **AND** a note with no links shows no related-notes affordance.

#### Scenario: Editor canvas is not compressed by property UI
- **WHEN** a note carries asset data, tags, and links simultaneously
- **THEN** the editor canvas occupies the remaining vertical space without inline property blocks reducing it
- **AND** the formatting toolbar sits directly above the canvas.
