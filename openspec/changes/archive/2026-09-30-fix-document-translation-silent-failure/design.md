## Context

See `proposal.md` for motivation. Currently, document translation during format conversion is scattered across `DocumentTranslator`, `OoxmlRewriter`, and `SpreadsheetmlRewriter`. Each re-implements batch partitioning, prompts, and parsing. All three silently catch exceptions, pretending the conversion succeeded with English text. Furthermore, `AiService`'s 60-second cooldown lock prevents immediate batch retries when only a single AI provider is configured.

## Goals / Non-Goals

**Goals:**
- Provide reliable document translation with fast, bounded batches (<= 30 items, <= 1500 chars).
- Fail fast and throw `DocumentTranslationException` when translation fails after retry, surfacing the error in the UI.
- Prevent transient batch failures from being blocked by provider cooldown when retrying.
- Implement DOM-based XML rewriting in `OoxmlRewriter` using `package:xml` to ensure valid document structure and avoid substring collisions.
- Unify translation batching and prompt execution into `DocumentTranslator`.

**Non-Goals:**
- Parallel batch execution (sequential batching is preferred to preserve context and avoid 429 rate limit triggers on third-party proxies).
- Changing OCR or PDF text extraction logic.

## Decisions

### 1. Dual-Constraint Batch Partitioning in `DocumentTranslator`
- **Decision**: Partition texts into batches satisfying `batch.length <= 30` AND `totalChars <= 1500`.
- **Rationale**: Short paragraphs in documents (tables, lists, headers) caused single batches to hold 175+ items, taking ~55s to process and risking output truncation. 30 items / 1500 chars completes in 5-8s per batch with smooth progress updates and low failure likelihood.
- **Alternatives considered**: Character-only budget (fails for documents with many short lines); Item-count-only budget (fails for long paragraph documents).

### 2. Centralized Translation Service (`DocumentTranslator`)
- **Decision**: `OoxmlRewriter`, `SpreadsheetmlRewriter`, and `SimpleRewriter` delegate all translation to `DocumentTranslator.translateStrings()` and `DocumentTranslator.translate()`.
- **Rationale**: Eliminates three duplicated implementations of prompting, batching, JSON parsing, and retry handling.

### 3. Fail-Fast Error Policy and UI Feedback
- **Decision**: If a batch fails twice, throw `DocumentTranslationException(message)`. In `ConvertDialog`, catch this exception and show a user-friendly error dialog ("文档翻译失败：..."), aborting file saving.
- **Rationale**: Never silently write an untranslated document when the user explicitly asked for translation.

### 4. Cooldown Bypass for In-Flight Document Retries
- **Decision**: In `AiService.chat`, support bypassing unhealthy cooldown checks when explicitly retrying an active document translation, or automatically retry the active candidate before marking unhealthy.
- **Rationale**: For users with a single configured AI provider, marking it unhealthy on a 1-second network glitch kills the entire document conversion because the retry is immediately blocked by `_isProviderHealthy()`.

### 5. DOM-based OpenXML Rewriting in `OoxmlRewriter`
- **Decision**: Parse `word/document.xml` using `XmlDocument.parse()`. Find `<w:p>` nodes, collect all `<w:t>` elements inside each paragraph, set the first `<w:t>`'s text to the translated paragraph text, and empty the remaining `<w:t>` elements.
- **Rationale**: Avoids `paraXml.indexOf(run.xml)` which fails on duplicate runs or empty formatting runs, and avoids string manipulation that corrupts XML entities.

## Risks / Trade-offs

- **[Risk]** More HTTP requests per document due to smaller batches.
  → **Mitigation**: Total wall-clock time is comparable or faster because smaller prompts generate much faster with lower model reasoning overhead, and failure recovery only requires re-requesting 30 items rather than 175 items.
- **[Risk]** XML formatting differences when serializing with `XmlDocument.toXmlString()`.
  → **Mitigation**: `package:xml` preserves node hierarchy, namespaces, and attributes. Verify with zip inspection and automated fidelity tests.
