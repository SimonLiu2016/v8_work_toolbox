## Purpose

定义 (源格式 × 目标格式) 文档转换矩阵的完整性与还原度分级：哪些组合必须可用、
每个组合承诺保留什么、以及不提供的组合如何在 UI 中缺席。缺乏这份契约时，
"一键转换"很容易退化成"部分格式能转、部分静默失败"，而用户无法预先知道
哪条路径值得信任。

## ADDED Requirements

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
The following matrix is normative. `T1` = Tier 1, `T2` = Tier 2, `—` = not offered.

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
