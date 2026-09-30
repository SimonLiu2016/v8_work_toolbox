## ADDED Requirements

### Requirement: Note attachments offer one-tap conversion
Every note attachment whose format appears in the conversion matrix SHALL offer a conversion action. Invoking it SHALL let the user choose a source language, a target language, and a target format drawn from that source's available row of the matrix, and SHALL produce a new attachment without altering the original.

#### Scenario: Converting an English Word attachment to Chinese Word
- **WHEN** the user chooses source English, target Chinese, and target format Word on a Word attachment
- **THEN** a new Word attachment is produced whose layout, images and styling match the original
- **AND** only the English text has been replaced by Chinese
- **AND** the original attachment is left untouched.

#### Scenario: Converting the same attachment to PDF
- **WHEN** the user chooses source English, target Chinese, and target format PDF on the same attachment
- **THEN** a new PDF attachment is produced containing the translated text and the original images
- **AND** the layout is a best-effort reconstruction, not a byte-level match.

#### Scenario: Only available targets are offered
- **WHEN** the target-format picker opens for a Word attachment
- **THEN** the offered formats are Word, PDF, Markdown and plain text
- **AND** spreadsheet formats are not offered.

#### Scenario: Output is a new attachment with a distinguishing name
- **WHEN** a conversion completes
- **THEN** the result is stored as a new attachment of the same note
- **AND** its name carries the target language and format so it is distinguishable from the source.
