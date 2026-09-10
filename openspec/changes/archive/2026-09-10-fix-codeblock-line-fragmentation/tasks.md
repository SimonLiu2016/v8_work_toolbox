## 1. Zero-Dependency ENML Parser & Language Extraction

- [x] 1.1 Implement native Python `HTMLParser` in `scripts/evernote_import.py` to remove `html2text` external dependency
- [x] 1.2 Parse `--en-meta:{"lang":"..."}` from Evernote code blocks and emit normalized ````lang fences
- [x] 1.3 Add safe fallback stripping so raw ENML/XML tags are never returned on parsing errors
- [x] 1.4 Add multi-candidate Python interpreter resolution in `lib/tools/notebook/evernote_import_service.dart`

## 2. Editor Delta Stream Line Aggregator

- [x] 2.1 Refactor `_sanitizeDeltaList` in `lib/tools/notebook/ui/note_editor.dart` to group consecutive `code-block` lines into single `code_block` embeds
- [x] 2.2 Drop empty `code_block` embeds (`code.trim().isEmpty`) during sanitization to heal corrupted notes
- [x] 2.3 Verify `markdown_converter.dart` roundtrip for multi-line code blocks

## 3. Database Re-import, Verification & Packaging

- [x] 3.1 Execute local Evernote re-import to restore clean markdown, images, mindmaps, and code blocks in `notebook.db`
- [x] 3.2 Run test suite and analyzer to verify all changes
- [x] 3.3 Build macOS release binary and update `/Applications/V8WorkToolbox.app` via `ditto`
