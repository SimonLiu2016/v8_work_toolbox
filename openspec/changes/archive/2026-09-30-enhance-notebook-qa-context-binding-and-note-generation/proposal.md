## Why

Currently, "问我的笔记" (Notebook QA) only performs blind global full-text keyword retrieval across all notes, extracting short snippets (800 characters) from top-matching notes. When users want to conduct in-depth analysis on a specific document—such as summarizing business flows, generating user guides, or detecting logical inconsistencies in the currently open note—the system either misses key context due to snippet truncation or retrieves irrelevant snippets from other notes.

Furthermore, once the AI produces comprehensive insights or structured summaries, users must manually copy and paste the text into new notes. Adding direct context binding (via a top Scope Capsule Bar and `@mention` autocomplete) and one-click note creation/appending bridges the gap between note reading, AI analysis, and knowledge production.

## What Changes

- **Active Note Scope Capsule Bar (Mode A)**:
  - Display a persistent context scope capsule bar at the top of the QA panel.
  - Automatically bind the currently open note (`[ 📄 当前笔记: <Title> ✕ ]`).
  - Allow unbinding with `✕` to switch back to global retrieval mode (`[ 🌐 全库检索 ]`), or clicking to pick a specific note.
- **`@Mention` Note Autocomplete in Input Box (Mode B)**:
  - In the QA input box, typing `@` triggers an autocomplete overlay listing notes filtered by keyword.
  - Selecting a note binds it as an explicit target reference for the question.
- **Targeted Note Full-Text Context & Tool Execution**:
  - Update `NotebookKbService.ask()` to accept explicit target note(s).
  - When target notes are provided, extract their full plain-text content and inject it directly into the primary prompt context, bypassing snippet truncation.
  - Keep agent tools (`notebook_search`, `web_search`, `scrape`) enabled during targeted queries so the model can cross-reference other notes or verify external information as requested.
- **Save & Append QA Answers as Notes**:
  - Add quick action buttons below each AI answer turn: `[ 📝 保存为新笔记 ]`, `[ 📋 追加到当前笔记 ]`, `[ 📑 复制回答 ]`.
  - "保存为新笔记" parses the answer's Markdown into rich-text document blocks (`AppFlowyCodec.parseToDocument`) and creates a new note in `NoteStore`, then opens it.
  - "追加到当前笔记" appends the generated content blocks directly into the currently bound note.

## Capabilities

### Modified Capabilities
- `notebook-tool`: Enhance "问我的笔记" with explicit note binding (Scope Capsule & @mention), targeted full-note context injection, tool execution during targeted queries, and one-click saving/appending of QA answers into notes.

## Impact

- `lib/tools/notebook/ui/notebook_qa_panel.dart`: Scope Capsule bar UI, `@mention` suggestion overlay, answer card action buttons.
- `lib/tools/notebook/ui/notebook_page.dart`: Wire active note changes to `NotebookQaPanel`, provide note creation/opening hooks.
- `lib/tools/notebook/notebook_kb_service.dart`: Add `targetNoteIds`/`targetNotes` parameter to `ask()`, format full-text prompt, retain agent loop tools.
- `lib/tools/notebook/appflowy_codec.dart` & `lib/tools/notebook/note_store.dart`: Interfacing with Markdown parsing and note insertion.
