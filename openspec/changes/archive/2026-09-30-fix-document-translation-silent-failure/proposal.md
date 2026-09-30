## Why

When users convert documents with translation enabled (e.g. Word English to Chinese via `ooxml_rewriter`), transient AI service errors or timeouts currently fail silently (`catch (_) {}`), resulting in 0% of the document translated while the application misleadingly reports 100% success and writes an untranslated file. Additionally, a massive single-batch size (up to 4000 characters with 175+ paragraphs) causes LLM generation timeouts (~55s), and provider-level 60-second cooldown locks in `AiService` prematurely abort retries and subsequent batches.

This change fixes document translation resilience, reduces batch size, eliminates silent failure fallbacks, surfaces explicit error reporting to the user interface, and improves OOXML XML rewriting fidelity using DOM-based parsing.

## What Changes

- **Resilient Translation Batching**: Cap batch size to a dual-constraint budget (max 30 items AND max 1500 characters) to ensure fast 5-8s roundtrips, smoother progress updates, and much lower failure rates.
- **Fail-Fast Error Propagation**: Remove silent `catch (_)` swallowing in `OoxmlRewriter`, `SpreadsheetmlRewriter`, and `DocumentTranslator`. If translation fails after retries, throw an explicit `DocumentTranslationException` so the UI clearly reports failure instead of saving an untranslated document.
- **Cooldown Bypass for Immediate Document Retries**: Provide an option or explicit call strategy in translation so transient errors do not trigger a 60-second cooldown lockout on the single configured AI provider.
- **DOM-based OOXML Replacement**: Replace fragile regex-based run string replacement (`indexOf(run.xml)`) with robust XML DOM element traversal using `package:xml`, preventing corrupted tags and duplicate run collision.
- **Unified Translation Layer**: Consolidate batching, prompt formatting, and JSON response parsing into `DocumentTranslator` so `OoxmlRewriter`, `SpreadsheetmlRewriter`, and `SimpleRewriter` share the same robust implementation.

## Capabilities

### New Capabilities
- `document-conversion-matrix`: Defines document conversion matrix resilience, translation batching, failure notification, and XML fidelity requirements for document conversion.

## Impact

- Modified files: `lib/tools/notebook/convert/translator.dart`, `lib/tools/notebook/convert/ooxml_rewriter.dart`, `lib/tools/notebook/convert/spreadsheetml_rewriter.dart`, `lib/tools/notebook/convert/ui/convert_dialog.dart`, and associated tests.
- UI: Convert dialog displays descriptive error dialogs upon translation failures instead of falsely claiming success.
- Dependencies: Uses existing `package:xml` and `AiService`.
