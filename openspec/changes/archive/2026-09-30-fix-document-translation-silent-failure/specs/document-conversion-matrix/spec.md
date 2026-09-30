## Purpose

Defines document translation resilience, granular batching constraints, explicit error notifications, and high-fidelity XML node rewriting for document format conversion.

## ADDED Requirements

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
