## ADDED Requirements

### Requirement: Note List Context Menu Actions
The notebook tool SHALL provide a comprehensive 13-item context menu upon secondary (right-click) tap on any note card in the middle-column note list.

#### Scenario: Right-click menu display
- **WHEN** a user right-clicks on a note card in the notes list
- **THEN** a context menu appears at the cursor location containing the 13 standard actions (新建笔记, 在新窗口中打开笔记, 添加笔记到快捷方式/从快捷方式移除, 创建任务, 共享笔记…, 演示, 导出笔记…, 将附件保存到文件夹…, 复制笔记链接, 移动笔记到…, 复制笔记到…, 创建笔记副本, 删除笔记).

#### Scenario: New note creation from context menu
- **WHEN** a user selects "新建笔记" from the context menu
- **THEN** a new blank note is created in the currently active notebook, selected in the list, and opened in the editor.

#### Scenario: Open note in standalone window
- **WHEN** a user selects "在新窗口中打开笔记"
- **THEN** an independent desktop sub-window is launched displaying only that note in full-featured view without disturbing the main window.

#### Scenario: Toggle note shortcuts pin status
- **WHEN** a user selects "添加笔记到快捷方式" or "从快捷方式中移除"
- **THEN** the note's pinned/shortcut status is toggled, sorting it accordingly and updating its pin indicator.

#### Scenario: Quick task checklist creation in note
- **WHEN** a user selects "创建任务"
- **THEN** a checklist todo checkbox item is appended to the note content and automatically saved.

#### Scenario: Share note options
- **WHEN** a user selects "共享笔记…"
- **THEN** a share modal is displayed providing options to copy Markdown, copy plain text, or generate a standalone offline HTML page.

#### Scenario: Distraction-free presentation mode
- **WHEN** a user selects "演示"
- **THEN** a clean, distraction-free large-typography presentation view is displayed for reading or demonstrating the note content.

#### Scenario: Export note from context menu
- **WHEN** a user selects "导出笔记…"
- **THEN** the export dialog is opened pre-configured for the selected note, allowing export to PDF, Markdown, HTML, or TXT.

#### Scenario: Save note attachments to folder
- **WHEN** a user selects "将附件保存到文件夹…"
- **THEN** the system prompts the user to select an output directory and extracts all images and attached files of the note to that directory.

#### Scenario: Copy note internal deep link
- **WHEN** a user selects "复制笔记链接"
- **THEN** the application deep link (`v8work://notebook/note/{id}`) and markdown link are copied to the system clipboard with toast feedback.

#### Scenario: Move note to another notebook
- **WHEN** a user selects "移动笔记到…" and chooses a destination notebook
- **THEN** the note's notebook association is updated to the destination notebook.

#### Scenario: Copy note to another notebook
- **WHEN** a user selects "复制笔记到…" and chooses a destination notebook
- **THEN** a full clone of the note is created inside the destination notebook with a new identifier.

#### Scenario: Duplicate note within current notebook
- **WHEN** a user selects "创建笔记副本"
- **THEN** an immediate duplicate of the note is created in the same notebook with title suffix " (副本)".

#### Scenario: Note deletion from context menu
- **WHEN** a user selects "删除笔记"
- **THEN** in active views the note is moved to trash, and in trash view the note is permanently deleted.

### Requirement: CJK Fidelity in PDF Document Export
The notebook export system SHALL render Chinese, Japanese, and Korean (CJK) characters with full typographical fidelity without glyph corruption, square replacement boxes, or question marks when exporting notes to PDF.

#### Scenario: Offline PDF export with system CJK font
- **WHEN** exporting a note containing Chinese text to PDF on macOS
- **THEN** the exporter loads the native macOS system CJK TrueType font and renders all characters without requiring network access.

#### Scenario: Fallback online CJK font rendering
- **WHEN** exporting a note to PDF and local system CJK fonts are unavailable
- **THEN** the exporter dynamically falls back to an embedded Google CJK font.

#### Scenario: Preserving Chinese characters across all PDF structural elements
- **WHEN** a note with Chinese titles, headers, paragraphs, bullet lists, and code blocks is exported to PDF
- **THEN** all text elements faithfully preserve Chinese glyphs and styling across multiple pages.
