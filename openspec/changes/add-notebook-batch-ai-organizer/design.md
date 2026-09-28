## Context

See `proposal.md` for motivation.
Currently, `NotebookKbService` supports single-note tag suggestions (`suggestTags`) and relationship link discovery (`suggestLinks`). The single-note workflow in `AiSuggestionDialog` requires manual multi-step checkmarks before committing to `NoteStore`.
The knowledge graph (`KnowledgeGraphView`) renders nodes by collecting notes participating in `note_links`. For users with many unlinked notes, bulk automated organization without repetitive clicks is required to populate the knowledge graph seamlessly.

## Goals / Non-Goals

**Goals:**
- Provide a clean, robust background batch runner (`BatchOrganizerService`) that iterates over candidate notes and applies tags and links directly.
- Add an embedded progress bar inside the `KnowledgeGraphView` header to display processing percentage, current note title, and a stop button without blocking modal UI.
- Support scope selection (All Notes vs Unconnected Notes Only) via a lightweight pre-run confirmation dialog.
- Guarantee fault tolerance so that individual note timeouts or LLM errors do not crash the batch loop.
- Automatically refresh the knowledge graph layout upon completion or early stop.

**Non-Goals:**
- Interactive item-by-item manual review dialog for the entire bulk collection (the user specifically chose fully automated direct ingestion).
- Distributed or multi-threaded background workers (sequential async iterations within Dart are sufficient and avoid LLM rate limits).
- Deleting or overwriting user-authored tags and existing relations.

## Decisions

### Decision 1: Dedicated Batch Organizer Engine (`BatchOrganizerService`)
- **Decision**: Encapsulate bulk execution into `lib/tools/notebook/batch_organizer_service.dart` rather than embedding business loops directly inside the Flutter Widget state.
- **Rationale**: Keeps `KnowledgeGraphView` focused on presentation and state rendering, enables clean unit testing of the batch loop with mock or test stores, and simplifies cancelation token handling.
- **Alternatives Considered**: Inlining the `for` loop inside `_KnowledgeGraphViewState`: would bloat the widget by 200+ lines and make unit testing difficult.

### Decision 2: Automated Direct Ingestion with Deduplication
- **Decision**: Candidate tags returned by `suggestTags` are created if missing and appended to the note's tags via `NoteStore.instance.setNoteTags`. Candidate links returned by `suggestLinks` are created via `NoteStore.instance.createLink`, with automatic rejection of self-loops and duplicate edges.
- **Rationale**: Fulfills user requirement 1 (Option A: fully automated direct ingestion). Eliminates hundreds of repetitive click confirmations.

### Decision 3: Embedded Non-Blocking Progress Banner in Graph Header
- **Decision**: When `isOrganizing` is true, the `KnowledgeGraphView._header` swaps its default title row with an embedded progress banner containing:
  1. Status text: `正在整理 (12/65 篇)：《系统架构》...`
  2. A thin `LinearProgressIndicator`
  3. A stop button `[ ⏹ 停止 ]`
- **Rationale**: Fulfills user requirement 3. Keeps the graph surface visible and interactive while processing proceeds smoothly.

### Decision 4: Pre-Run Scope Configuration Dialog
- **Decision**: Clicking "批量AI整理" queries `NoteStore` for active note count and unlinked note count, then pops a modal dialog with:
  - Radio options: "全部笔记 (N 篇)" and "仅未关联笔记 (M 篇)"
  - Action buttons: "取消" and "开始整理"
- **Rationale**: Fulfills user requirement 2. Prevents accidental execution and gives the user control to save time and API tokens if they only want to organize unlinked notes.

### Decision 5: Sequential Execution with Cooperative Cancellation & Error Isolation
- **Decision**: Process notes sequentially with `for (final note in queue)`. Check `cancellationToken.isCancelled` before each note. Wrap each note's tag and link processing in a `try-catch` block.
- **Rationale**:
  - LLM providers typically enforce concurrency and rate limits (RPM/TPM). Sequential execution provides the most reliable throughput without 429 errors.
  - If a single note fails (e.g. malformed unicode or network blip), the error is recorded and the loop continues with the next note.
  - Trivial notes (blank content or < 5 characters) are skipped instantly without network overhead.

## Risks / Trade-offs

- **[Risk] High API latency or rate limiting during large note batches** → Mitigation: Sequential execution with 50ms cooldown between notes; users can cancel at any time via the "停止" button and resume later using "仅未关联笔记".
- **[Risk] Unintended AI-generated tags cluttering user tags** → Mitigation: `suggestTags` already checks existing tag dictionary and filters duplicates; tags created are visible in the tag drawer and can be managed normally.
- **[Risk] UI jank during graph updates** → Mitigation: Defer force-directed layout updates until batch completion or early termination, rather than re-laying out the physics canvas after every single note.
