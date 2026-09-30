## Purpose

Defines document format conversion matrix completeness, fidelity tiers, independent translation capability, translation resilience and batching, failure notifications, and high-fidelity XML node rewriting for the document format conversion system.

## Requirements

### Requirement: The conversion matrix is complete for every marked cell
For every (source format, target format) pair marked as available, the application SHALL provide a conversion path. A pair marked available but not implemented SHALL NOT exist. Equally, a pair marked unavailable SHALL NOT appear as a selectable target.

#### Scenario: Every available cell has a path
- **WHEN** the conversion matrix is inspected
- **THEN** each cell marked as available resolves to a working conversion
- **AND** no available cell is unimplemented.

#### Scenario: Unavailable cells are absent from the target picker
- **WHEN** the user opens the target-format picker for a given source format
- **THEN** only the formats marked available for that source are offered
- **AND** a format that cannot honour the content-fidelity promise is not offered at all.

### Requirement: Fidelity tier is declared per cell and honoured
Each available cell SHALL declare its fidelity tier, and the conversion SHALL honour that declaration.

- **Tier 1 (layout-preserving)** — the target preserves layout, images and styling byte-for-byte apart from the replaced text. Achieved by rewriting text nodes in place.
- **Tier 2 (content-preserving)** — the target preserves all content and images, with best-effort layout reconstruction.

#### Scenario: Tier 1 conversion leaves everything but text untouched
- **WHEN** a Tier 1 conversion runs (for example Word to Word, or Excel to Excel)
- **THEN** the output replaces only the text nodes of the source
- **AND** embedded images, styles, tables and document structure are unchanged.

#### Scenario: Tier 2 conversion keeps content and images
- **WHEN** a Tier 2 conversion runs (for example Word to PDF, or Word to Markdown)
- **THEN** all textual content and embedded images are present in the output
- **AND** layout is reconstructed on a best-effort basis, which the product describes as such rather than promising an exact match.

### Requirement: Translation and format conversion are independent
The user SHALL be able to run translation without changing format, to change format without translating, and to do both in one pass.

#### Scenario: Translate only
- **WHEN** the user requests translation with the target format equal to the source format
- **THEN** the output is in the source format with the text translated.

#### Scenario: Convert only
- **WHEN** the user requests conversion with no translation
- **THEN** the output is in the target format with the text unchanged.

#### Scenario: Both
- **WHEN** the user requests both translation and conversion
- **THEN** the output is in the target format with the text translated.

### Requirement: The full availability matrix
The document conversion system SHALL conform to the following normative matrix. `T1` = Tier 1, `T2` = Tier 2, `—` = not offered.

| Source \ Target | docx | pdf | md | txt | xlsx | csv |
|---|---|---|---|---|---|---|
| **docx** | T1 | T2 | T2 | T2 | — | — |
| **md**   | T2 | T1 | T2 | T2 | — | — |
| **txt**  | T1 | T1 | T1 | T1 | — | — |
| **pdf**  | — | T2 | T2 | T2 | — | — |
| **xlsx** | T2 | T2 | T2 | T2 | T1 | T2 |
| **csv**  | T2 | T2 | T2 | T2 | T2 | T1 |

#### Scenario: Matrix conformance is machine-checked
- **WHEN** the matrix table above is compared against the implementation's cell registry
- **THEN** every non-empty cell is implemented and every empty cell is absent from the picker
- **AND** a mismatch fails the build rather than shipping a silently unsupported path.

#### Scenario: Prose never lands in a spreadsheet target from a document source
- **WHEN** the source is a flowing document (`docx`, `md`, `txt`, `pdf`)
- **THEN** spreadsheet targets (`xlsx`, `csv`) are not offered
- **AND** this reflects that mapping prose into a table has no defensible interpretation.

### Requirement: Source-language documents without a text layer are reported, not mis-converted
When a source document has no extractable text layer (for example a scanned PDF), the conversion SHALL report that condition rather than producing an empty or misleading output.

#### Scenario: Scanned PDF conversion attempt
- **WHEN** the user requests conversion of a PDF with no text layer
- **THEN** the application reports that the PDF has no text layer
- **AND** no output file is produced that would appear to be a successful conversion.

### Requirement: Document translation batching is bounded by item count and character limit
The document translation engine SHALL partition extracted translatable text segments into batches bounded by both a maximum item count of 30 segments and a character budget of 1500 characters per batch.

#### Scenario: Document containing numerous short paragraphs
- **WHEN** a document with over 100 short headings or bullet points is translated
- **THEN** the translation engine partitions the text into batches of at most 30 items
- **AND** no batch exceeds 1500 total characters
- **AND** each batch completes in an acceptable roundtrip time without model timeouts.

### Requirement: Translation failures are surfaced without false success completion
When AI translation fails due to network disconnection, provider timeout, or unparseable responses after retry, the conversion engine SHALL throw an explicit translation exception and the UI SHALL display a failure message. The application SHALL NOT pretend conversion succeeded or write untranslated text under a translated file name.

#### Scenario: AI translation endpoint unreachable or times out
- **WHEN** the user initiates document conversion with translation enabled and the AI service times out or errors
- **THEN** the system aborts the conversion process and presents an error dialog explaining the translation failure
- **AND** no corrupted or untranslated output attachment is generated as a successful conversion.

### Requirement: Document translation retries bypass single-provider lockout cooldown
During document translation, transient request failures for a batch SHALL be retried without being blocked by temporary provider cooldown periods when no alternative candidate provider exists.

#### Scenario: Transient network hiccup during a batch
- **WHEN** a batch translation encounters a transient network disconnect on the sole configured provider
- **THEN** the translation engine retries the batch
- **AND** the retry request is not immediately aborted by a 60-second cooldown block.

### Requirement: Word document in-place rewriting replaces XML text runs via DOM
The OOXML rewriter SHALL parse `word/document.xml` using an XML DOM parser and replace `<w:t>` text nodes directly within `<w:p>` paragraphs rather than relying on raw string substring search or index slicing.

#### Scenario: Paragraph contains duplicate or empty run tags
- **WHEN** a Word document paragraph contains multiple identical runs or empty runs
- **THEN** the DOM-based rewriter updates the text nodes without misaligning subsequent runs or producing invalid XML syntax.
