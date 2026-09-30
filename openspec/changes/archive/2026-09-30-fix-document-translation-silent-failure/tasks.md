## 1. Unified Translation Service & Resilient Batching

- [x] 1.1 Implement dual-constraint batching (`maxBatchItems = 30`, `maxCharBudget = 1500`) in `DocumentTranslator`
- [x] 1.2 Define `DocumentTranslationException` and remove silent `catch (_)` swallowing in `DocumentTranslator`
- [x] 1.3 Support cooldown bypass or retry protection in `AiService.chat` for translation requests
- [x] 1.4 Expose unified `DocumentTranslator.translateStrings()` with progress callbacks for all rewriters

## 2. OOXML & SpreadsheetML Rewriter Refactoring

- [x] 2.1 Refactor `OoxmlRewriter` to delegate translation to `DocumentTranslator.translateStrings()`
- [x] 2.2 Implement DOM-based XML rewriting in `OoxmlRewriter` using `package:xml` (`XmlDocument.parse`)
- [x] 2.3 Refactor `SpreadsheetmlRewriter` to delegate translation to `DocumentTranslator.translateStrings()` and remove silent swallowing

## 3. UI Error Handling in Convert Dialog

- [x] 3.1 Catch `DocumentTranslationException` and conversion errors in `ConvertDialog._startConversion()`
- [x] 3.2 Display an informative error message on translation/conversion failure and abort attachment saving

## 4. Verification & Testing

- [x] 4.1 Add unit tests for dual-constraint batching and exception throwing on translation failures
- [x] 4.2 Add unit test for DOM-based OOXML run text replacement
- [x] 4.3 Run end-to-end translation on `Seatrium User Manual` sample docx and verify Chinese characters in output
- [x] 4.4 Run full test suite and `flutter analyze`
