## Why

Two critical issues impair note readability and import reliability:
1. When importing or re-importing Evernote notes in the packaged macOS application, the process silently failed because `scripts/evernote_import.py` depended on an external `html2text` pip package not present in macOS system `/usr/bin/python3`. The silent exception fallback returned raw ENML markup (`<!DOCTYPE en-note ...>`), polluting note content with raw XML/HTML tags.
2. In the note editor, opening notes with legacy Quill line-by-line `code-block: true` attributes fragmented each code line into plain text followed by an empty code block embed showing `// 暂无代码内容`.

We need a zero-dependency standard-library ENML parser that runs anywhere without pip packages, paired with robust Python interpreter resolution and a stream line-aggregator in the note editor to produce clean, unified multi-line code blocks with proper syntax highlighting.

## What Changes

- **Zero-dependency ENML conversion**: Replace external `html2text` with a native Python standard library `html.parser.HTMLParser` implementation in `scripts/evernote_import.py`. Eliminate all external pip dependencies from the local import flow and guarantee raw XML tags are never leaked into notes.
- **Evernote codeblock metadata extraction**: Extract `--en-meta:{"lang":"..."}` from Evernote code blocks to generate language-tagged markdown code fences (e.g. ````yaml`, ````bash`, ````sql`).
- **Python binary resolution**: Enhance `evernote_import_service.dart` to discover and use available Python 3 interpreters (Homebrew, Conda, system).
- **Editor stream line-aggregator**: Fix `_sanitizeDeltaList` in `note_editor.dart` to properly group consecutive `code-block` lines into a single `code_block` embed.
- **Database healing and re-import**: Provide automatic healing / clean re-import for local `notebook.db` so notes display clean text and formatted code blocks.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `notebook-tool`: Refine the code block rendering and Evernote import requirements to guarantee robust zero-dependency ENML conversion, native code language extraction, and continuous multi-line stream aggregation.

## Impact

- Affected code: `scripts/evernote_import.py`, `lib/tools/notebook/evernote_import_service.dart`, `lib/tools/notebook/ui/note_editor.dart`, `lib/tools/notebook/markdown_converter.dart`.
- Dependencies: Completely removes external pip dependency `html2text`.
- Local database: Restores clean notes in `notebook.db`.
