## Context

See `proposal.md` for motivation. In macOS packaged applications, `Process.run('python3')` invokes `/usr/bin/python3`, which lacks user-installed site-packages like `html2text`. When `import html2text` failed, `convert_enml_to_markdown` fell back to returning raw ENML. Furthermore, Quill Delta stores code blocks with trailing `\n` attributes, which requires stream line-level aggregation when converting to embed cards.

## Goals / Non-Goals

**Goals:**
- Implement a pure Python standard library `ENMLToMarkdownParser` (using `html.parser.HTMLParser`) with zero external pip dependencies.
- Safely sanitize and strip any unhandled HTML/XML tags so raw `<!DOCTYPE en-note>` is never leaked.
- Extract language metadata from `--en-meta:{"lang":"..."}` and map to normalized identifiers (`bash`, `yaml`, `json`, `sql`, etc.).
- Robust Python discovery in `evernote_import_service.dart` probing Homebrew, Conda, and system paths.
- Stream line-aggregator in `note_editor.dart` `_sanitizeDeltaList` to cleanly group `code-block` lines and discard invalid empty code embeds.
- Re-import and heal local database `notebook.db`.

**Non-Goals:**
- Replacing Quill or other embed types.

## Decisions

1. **Pure Python HTMLParser for ENML**:
   - Subclass `html.parser.HTMLParser` from the Python standard library.
   - Handle headers (`h1`-`h6`), paragraphs (`p`, `div`), line breaks (`br`), lists (`ul`, `ol`, `li`), links (`a`), text formatting (`b`, `strong`, `i`, `em`, `u`, `s`), images/media (`en-media`), and checkboxes (`en-todo`).
   - For codeblocks (`--en-codeblock:true` or `<pre><code>`), intercept the full raw code and language tag from `--en-meta` before HTML parsing, replacing them with unique placeholders `__EVERNOTE_CODEBLOCK_N__`, and restoring them as ````lang\ncode\n```` at the end.
   - Fallback guarantee: Even if an unhandled XML error occurs, run regex tag stripper `re.sub(r'<[^>]+>', '', ...)` instead of returning raw markup.

2. **Delta Stream Line Aggregator**:
   - Collect pending line pieces (text strings and embeds) until `\n`.
   - Inspect the `\n` attributes:
     - If `attributes['code-block'] == true`:
       - Append the line's text to an active code block buffer.
       - Continue reading consecutive lines until a line without `code-block` or end of document.
       - Emit a single `code_block` embed followed by `\n`.
     - Otherwise:
       - Flush pending line pieces and newline normally.
   - For existing embed ops: If an embed is `code_block` with empty code (`""`), discard it.

3. **Re-import Execution**:
   - Run the updated import script to regenerate clean markdown and Delta embeds for `notebook.db`.

## Risks / Trade-offs

- [Risk] Custom HTMLParser might format complex tables differently than `html2text`.
  → Mitigation: Simple markdown table formatting in `HTMLParser`, which is more than sufficient for Evernote notes.
