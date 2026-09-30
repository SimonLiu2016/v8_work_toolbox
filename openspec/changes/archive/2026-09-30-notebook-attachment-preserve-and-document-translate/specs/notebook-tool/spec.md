## ADDED Requirements

### Requirement: Document Import Carries Embedded Images
The notebook tool SHALL import a locally chosen document (`pdf`, `docx`, `xlsx`, `md`, `markdown`, `txt`) as a new note, converting its content into the note body. Any images embedded in the source document SHALL be carried into the note body at their original positions and persisted as attachments of that note. An import that would drop an embedded image SHALL surface that loss to the user rather than completing silently.

#### Scenario: Import converts body text into a note
- **WHEN** the user imports a `docx` containing paragraphs and headings
- **THEN** a new note is created whose body preserves the paragraph and heading structure of the source.

#### Scenario: Import carries embedded images
- **WHEN** the user imports a document that contains embedded images
- **THEN** each embedded image appears in the note body at its position in the source
- **AND** each image is persisted as an attachment of the note.

#### Scenario: Import reports an unrecoverable image
- **WHEN** an embedded image cannot be extracted from the source document
- **THEN** the import result reports the count of images that could not be carried over
- **AND** the import does not present itself as a complete success.
