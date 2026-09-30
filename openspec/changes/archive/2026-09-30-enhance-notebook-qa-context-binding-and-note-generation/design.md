## Context

See `proposal.md` for motivation.

The current notebook system consists of:
- `NotebookPage` (`lib/tools/notebook/ui/notebook_page.dart`): The central workspace managing active notebooks, notes, editors, and the sliding `NotebookQaPanel`.
- `NotebookQaPanel` (`lib/tools/notebook/ui/notebook_qa_panel.dart`): Renders chat turns, a bottom input bar, and communicates with `NotebookKbService`.
- `NotebookKbService` (`lib/tools/notebook/notebook_kb_service.dart`): Manages full-text indexing, SQLite snippet retrieval, and runs `AgentLoop` with `notebook_search`, `web_search`, and `scrape` tools.
- `AppFlowyCodec` (`lib/tools/notebook/appflowy_codec.dart`): Bridges Markdown, JSON, and AppFlowy document models.
- `NoteStore` (`lib/tools/notebook/note_store.dart`): SQLite-backed note CRUD and FTS5 indexing.

Currently, `NotebookQaPanel` operates in isolation from the active note editor, executing global FTS keyword retrieval without knowing which note the user is reading or working on.

## Goals / Non-Goals

**Goals:**
- Provide direct note context binding via both a top Scope Capsule Bar (Mode A) and an inline `@mention` popup menu in the input box (Mode B).
- Supply full-text plain content of targeted note(s) into the LLM context, bypassing 800-character snippet truncation.
- Preserve agent tool calling (`notebook_search`, `web_search`, `scrape`) during targeted queries to enable cross-referencing and external verification.
- Provide one-click actions on AI answer cards to "Save as New Note" and "Append to Current Note".

**Non-Goals:**
- Multi-turn conversational git-like diff/patch merging within note editor blocks.
- Real-time collaborative multi-user prompt injection.
- Re-architecting the underlying FTS5 search index engine.

## Decisions

### 1. Dual-Mode Context Selection (Capsule Bar + @Mention)
- **Rationale**: 
  - **Mode A (Scope Capsule Bar)** is optimal when a user has a note open in the editor and wants to ask several questions about it without having to type `@` each time.
  - **Mode B (`@mention` autocomplete)** allows users in global search mode or multi-note workflows to reference one or more specific notes on the fly.
- **Alternatives considered**:
  - *Only @mentions*: Forces repeated typing when chatting extensively about the active note.
  - *Only Scope Bar*: Clunky if the user wants to reference a second note while discussing the first.

### 2. Full-Text Injection vs FTS Snippet Extraction for Targeted Notes
- **Rationale**: When a note is explicitly targeted, snippet retrieval (which truncates at 800 characters) fails to provide comprehensive context for global summarization, process extraction, or logical review. Modern LLMs easily handle 4k–32k token contexts; injecting the complete note plain text ensures the LLM sees the complete document structure and details.
- **Token Budget Guard**: If a targeted note exceeds 30,000 characters, truncate gracefully with a notification notice rather than causing token overflow.

### 3. State Synchronization between `NotebookPage` and `NotebookQaPanel`
- `NotebookPage` passes `activeNote` (`Note?`) and callbacks (`onOpenNote`, `onRefreshNotes`) to `NotebookQaPanel`.
- `NotebookQaPanel` tracks `_scopedNote` and `_userClearedScope`:
  - When `widget.activeNote` changes, if the user hasn't explicitly dismissed the scope for this note, auto-bind the new note.
  - If the user clicks `✕` on the capsule, set `_userClearedScope = true` and `_scopedNote = null`.

### 4. Rich Note Generation via `AppFlowyCodec.parseToDocument`
- Answers are formatted in standard Markdown.
- To "Save as New Note", use `AppFlowyCodec.parseToDocument(answerMarkdown)` to produce native AppFlowy blocks (headings, bullet points, checklists, code blocks, tables), convert to JSON delta, and persist via `NoteStore.instance.createNote`.
- This ensures newly created notes look native and maintain full formatting fidelity inside the rich-text editor.

## Risks / Trade-offs

- **[Risk] Large Note Token Consumption**: An exceptionally lengthy note could exceed prompt limits.
  → **Mitigation**: Truncate note text to a safe threshold (e.g. 30,000 characters) with a clear header annotation in the prompt if truncation occurs.
- **[Risk] Autocomplete Overlay Positioning**: Floating overlay in a narrow sidebar panel might cause layout overflow or keyboard collision.
  → **Mitigation**: Position the popup suggestion box directly above the input box using `CompositedTransformFollower` or an aligned overlay clamped to panel width.
- **[Risk] Append conflict with active editor**: Appending content to a currently open note while the editor is active might cause race conditions or unsaved editor state overwrite.
  → **Mitigation**: When appending to the active note, use the editor's live document controller if available, or reload the note in the editor after persistence.
