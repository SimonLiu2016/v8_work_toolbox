## ADDED Requirements

### Requirement: Note List Context Menu Actions
The notebook tool SHALL provide a 10-item context menu upon secondary (right-click) tap on any note card in the middle-column note list.

#### Scenario: Right-click menu display with dynamic states
- **WHEN** a user right-clicks on a note card in the notes list
- **THEN** a macOS-style context menu appears at the exact cursor coordinates containing the 10 standard actions, with "从快捷方式中移除" displayed if `isPinned` is true (otherwise "添加笔记到快捷方式"), and "粉碎笔记" displayed in red text if currently viewing the Trash.

#### Scenario: New note creation from context menu
- **WHEN** a user selects "新建笔记" from the context menu
- **THEN** a new blank note is created in the currently active notebook, selected in the list, and opened in the editor with focus on the title field.

#### Scenario: Open note in standalone window
- **WHEN** a user selects "在新窗口中打开笔记"
- **THEN** an independent desktop sub-window is launched displaying only that note in full-featured view, or brings an existing sub-window for that note to the foreground if already open.

#### Scenario: Middle column reflects edits made in a sub-window
- **WHEN** a note is edited and saved in a standalone sub-window, and the user returns focus to the main window
- **THEN** the middle-column note list refreshes to show the updated title and preview text.

#### Scenario: Toggle note shortcuts pin status
- **WHEN** a user selects "添加笔记到快捷方式" or "从快捷方式中移除"
- **THEN** the note's `isPinned` status is toggled, persisting to the database, sorting the note list with pinned notes at the top, and displaying a toast confirmation.

#### Scenario: Quick task checklist creation in note
- **WHEN** a user selects "创建任务"
- **THEN** an unchecked checklist todo item is appended to the end of the note's content and persisted, with visual toast confirmation.

#### Scenario: Share note options
- **WHEN** a user selects "共享笔记…"
- **THEN** a share modal is displayed providing options to copy Markdown, copy plain text, or generate and save a standalone offline HTML page.

#### Scenario: Export note from context menu
- **WHEN** a user selects "导出笔记…"
- **THEN** the export dialog is opened pre-configured for the selected note, allowing export to PDF, Markdown, HTML, or TXT.

#### Scenario: Save note attachments to folder
- **WHEN** a user selects "将附件保存到文件夹…"
- **THEN** the system scans the note for images and attachment files, prompts the user to select an output directory via native file picker, and copies all attachments to that directory using their original filenames with success feedback.

#### Scenario: Copy note internal deep link
- **WHEN** a user selects "复制笔记链接"
- **THEN** the application deep link (`v8work://notebook/note/{id}`) and markdown link format are copied to the system clipboard with toast feedback.

#### Scenario: Move note to another notebook
- **WHEN** a user selects "移动笔记到…" and chooses a destination notebook from a dialog
- **THEN** the note's notebook association is updated to the destination notebook, refreshing both current and target notebook views.

#### Scenario: Note deletion from context menu
- **WHEN** a user selects "删除笔记"
- **THEN** in active views the note is moved to trash with an Undo toast option, and in trash view a confirmation dialog appears before permanently destroying the note.

### Requirement: CJK Fidelity in PDF Document Export
The notebook export system SHALL render Chinese, Japanese, and Korean (CJK) characters with full typographical fidelity without glyph corruption, square replacement boxes, or question marks when exporting notes to PDF.

#### Scenario: Offline PDF export with system CJK font
- **WHEN** exporting a note containing Chinese text to PDF on macOS
- **THEN** the exporter loads the native macOS system CJK TrueType font (`/System/Library/Fonts/Supplemental/Arial Unicode.ttf`) and renders all characters without requiring network access.

#### Scenario: CJK font applies to every rendered text element
- **WHEN** a note with Chinese titles, headers, paragraphs, bullet lists, and code blocks is exported to PDF
- **THEN** all text elements faithfully preserve Chinese glyphs and styling across multiple pages, including text rendered with per-element inline styles.

#### Scenario: Graceful degradation when no system CJK font exists
- **WHEN** exporting a note to PDF and no local system CJK font can be located
- **THEN** the export still completes using the built-in font fallback without attempting any network access.
