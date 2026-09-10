## 1. UI Window Clearance and Theme Cohesion

- [x] 1.1 Add 30px top safe padding to sidebar header in `lib/tools/notebook/ui/notebook_page.dart` to clear macOS traffic lights
- [x] 1.2 Wrap `NoteEditor` in unified light theme with dedicated `QuillIconTheme` to eliminate dark toolbar background

## 2. Dependencies and Mind Map Support

- [x] 2.1 Add `flutter_svg` dependency in `pubspec.yaml`
- [x] 2.2 Update `scripts/evernote_import.py` and `lib/tools/notebook/markdown_converter.dart` to extract SVG data URLs and mind map JSON
- [x] 2.3 Implement `NoteMindMapEmbedBuilder` in `lib/tools/notebook/ui/note_editor.dart` with SVG zoom/pan and outline view

## 3. Professional Code Blocks

- [x] 3.1 Implement `NoteCodeBlockEmbedBuilder` with language picker, line numbers, copy button, and format option using `flutter_highlight`
- [x] 3.2 Support conversion between markdown code fences and enhanced code block embeds in `lib/tools/notebook/markdown_converter.dart`

## 4. Interactive Image Manipulation and Clipboard Paste

- [x] 4.1 Update `NoteImageEmbedBuilder` with selection borders, drag resize handles, and size presets
- [x] 4.2 Add context menu (copy, cut, delete) to image embeds
- [x] 4.3 Implement Cmd+V clipboard image paste listener in `lib/tools/notebook/ui/note_editor.dart`

## 5. Verification and Application Build

- [x] 5.1 Run tests and code analysis to verify all changes
- [x] 5.2 Build release macOS app and replace `/Applications/V8WorkToolbox.app`
