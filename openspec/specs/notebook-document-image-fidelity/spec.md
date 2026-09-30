# notebook-document-image-fidelity Specification

## Purpose
定义文档导入时内嵌图片的保真契约：图片必须按其在原文中的位置进入笔记，并以附件形式持久化，不再"导入即丢弃"；承载图片的附件块必须能内联预览，而非只显示图标。
## Requirements
### Requirement: Embedded images survive document import
When a document containing embedded images is imported as a note, every embedded image SHALL be extracted and carried into the note at the position it occupied in the source document. An image MUST NOT be silently dropped.

#### Scenario: Word document with images
- **WHEN** the user imports a `.docx` that contains embedded images
- **THEN** each image is extracted from the package's media store and referenced from the note body
- **AND** the note shows the same number of images as the source document
- **AND** each image appears at the position corresponding to its anchor in the source, not collected at the end.

#### Scenario: Image bytes are persisted through the attachment mechanism
- **WHEN** an imported image is written
- **THEN** its bytes land in the note's attachment directory and the note body references that attachment
- **AND** the image remains resolvable after the note is closed and reopened.

#### Scenario: PDF document with images
- **WHEN** the user imports a `.pdf` that contains embedded images
- **THEN** the embedded images are extracted per page and referenced from the note body
- **AND** text extraction behaviour is unchanged.

### Requirement: Attachment blocks render image previews
An attachment node whose MIME type is an image SHALL render an image preview in the note body, while non-image attachments SHALL keep their existing icon-plus-filename presentation.

#### Scenario: Image attachment is visible inline
- **WHEN** a note body contains an attachment node with an image MIME type
- **THEN** the block renders a preview of that image
- **AND** activating the preview opens the original image.

#### Scenario: Non-image attachment presentation unchanged
- **WHEN** a note body contains an attachment node for a non-image file
- **THEN** the block renders its file-type icon and filename exactly as before this capability existed.

