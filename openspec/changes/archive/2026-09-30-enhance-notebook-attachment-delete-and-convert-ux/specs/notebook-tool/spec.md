## ADDED Requirements

### Requirement: Attachment blocks offer deletion with confirmation and cleanup
Every attachment block (including embedded image blocks) rendered in the notebook SHALL provide a delete action. Invoking it SHALL prompt the user for confirmation, and upon confirmation, SHALL remove the block node from the document and remove the underlying attachment record and cached file from storage.

#### Scenario: Deleting an attachment block from a note
- **WHEN** the user clicks the delete button on an attachment or image block and confirms the action
- **THEN** the attachment block is removed from the active editor document
- **AND** the corresponding attachment database record and local storage file are deleted
- **AND** other content in the note remains intact.

#### Scenario: Canceling attachment block deletion
- **WHEN** the user clicks the delete button on an attachment block but cancels the confirmation dialog
- **THEN** the block remains in the document
- **AND** the attachment file and record are preserved.

### Requirement: Conversion flow provides explicit output location and note insertion
When an attachment conversion completes, the system SHALL inform the user of the concrete output file location, offer actions to reveal the file in Finder and open it, and SHALL insert the converted file as a new attachment block directly in the current note document.

#### Scenario: Successful conversion inserts output into note document
- **WHEN** an attachment conversion succeeds
- **THEN** a new attachment block representing the converted document is inserted into the active note immediately following the source block or appended to the document
- **AND** the user can see and interact with the newly converted document in the note editor.

#### Scenario: Successful conversion offers direct reveal and open actions
- **WHEN** an attachment conversion finishes
- **THEN** the conversion dialog presents the output filename and location
- **AND** provides clickable actions to reveal the output in Finder and open the output file with the default application.
