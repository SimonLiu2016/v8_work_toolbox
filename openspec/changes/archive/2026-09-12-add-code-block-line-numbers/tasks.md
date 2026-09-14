## 1. Code Block Line Numbers UI

- [x] 1.1 Implement line number calculation and sticky gutter widget in `NoteCodeBlockComponentWidget`.
- [x] 1.2 Align gutter and code editor typography, and wrap code input in horizontal scroll.
- [x] 1.3 Add gutter click-to-focus handler routing focus to the code `TextField`.

## 2. Verification & Deployment

- [x] 2.1 Add unit and widget tests in `test/code_block_line_numbers_test.dart` and verify all notebook tests pass.
- [x] 2.2 Run static analysis (`flutter analyze lib/tools/notebook/`) to confirm 0 issues.
- [x] 2.3 Build macOS release binary and deploy to `/Applications/V8WorkToolbox.app` via `ditto`.
