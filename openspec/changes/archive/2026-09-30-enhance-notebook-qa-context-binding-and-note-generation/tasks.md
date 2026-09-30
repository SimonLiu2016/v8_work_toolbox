## 1. NotebookKbService Target Note Context Injection

- [x] 1.1 Extend `NotebookKbService.ask()` to accept `targetNotes` parameter
- [x] 1.2 Implement full-text plain-content extraction for targeted notes with safety truncation threshold
- [x] 1.3 Format high-priority targeted note prompt context while retaining `AgentLoop` tool execution (`notebook_search`, `web_search`, `scrape`)
- [x] 1.4 Add unit tests verifying prompt formatting and tool availability during targeted note queries

## 2. Scope Capsule Bar in NotebookQaPanel

- [x] 2.1 Update `NotebookQaPanel` parameters to accept `activeNote` and note operation callbacks
- [x] 2.2 Build the persistent Scope Capsule Bar widget displaying active note pill with unbind `✕` or global search mode
- [x] 2.3 Add note picker dialog/menu when clicking the scope capsule to allow binding any specific note
- [x] 2.4 Implement scope state lifecycle (auto-sync with active note, respect manual unbinding)

## 3. At-Mention Note Autocomplete in QA Input

- [x] 3.1 Implement `@` trigger detection and keyword extraction in QA input text controller
- [x] 3.2 Build anchored autocomplete overlay displaying notes matching the search keyword
- [x] 3.3 Implement note selection handling to attach the chosen note reference to the question context
- [x] 3.4 Add keyboard navigation (Up/Down/Enter/Escape) and click-outside dismissal for the overlay

## 4. Actionable QA Results: Saving and Appending Notes

- [x] 4.1 Add action buttons ("保存为新笔记", "追加到当前笔记", "复制") to answer turn cards
- [x] 4.2 Implement "保存为新笔记" flow using `AppFlowyCodec.parseToDocument` and `NoteStore.createNote`, opening the created note
- [x] 4.3 Implement "追加到当前笔记" flow appending converted blocks to the active note document
- [x] 4.4 Add user feedback toasts and error handling for saving and appending actions

## 5. Integration, Polish, and Verification

- [x] 5.1 Wire `NotebookPage` active note state, document updates, and navigation callbacks to `NotebookQaPanel`
- [x] 5.2 Verify layout constraints within the narrow QA panel column to prevent overflow
- [x] 5.3 Implement widget/unit tests covering scope capsule, @mention triggering, and answer note creation
- [x] 5.4 Run static analysis (`flutter analyze`) and project test suite (`flutter test`)
