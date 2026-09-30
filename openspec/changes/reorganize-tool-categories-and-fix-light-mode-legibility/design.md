## Context

See `proposal.md` — Why. This section covers only the constraints that shape the approach.

Relevant current state:

- `ToolCategory` (`lib/tools/tool_definition.dart:15`) has four values. `ToolRegistry` (`lib/tools/registry.dart:350`) holds 16 tools; their distribution is file:4, build:1, system:10, privacy:2.
- `ActivityBar` (`lib/shell/activity_bar.dart:86`) renders `ToolCategory.values` minus `privacy` directly — adding an enum value automatically adds an activity-bar entry, with no per-category wiring.
- `AppShell` mirrors a recency list in memory: `SettingsStore.getRecentToolIds()/recordToolUsed()` (`lib/services/settings_store.dart:355`) → `AppShell._recentToolIds` (`lib/shell/app_shell.dart:44`). It is read once in `initState()` to pick the initial selection, and is **not** a usage counter — the distinction matters for Decision 2.
- `AppShell.selectTool()` (`lib/shell/app_shell.dart:96`) returns early for `openInNewWindow` tools, **before** `_recordUsage()`. That is why the three separate-window tools never entered the recency list at all.
- Theme tokens are complete: `accentText`, `accentSolid`, `onAccentSolid` (`lib/theme/app_theme.dart:345-349`), with light values `#4F46E5` / `#4F46E5` / white and dark `#A5B4FC` / `#4F46E5` / white (`app_theme.dart:411-413`).
- The project already opens external URLs with `Process.run('open', [...])` in 8 places, including local file paths; `url_launcher` is not a dependency and is not needed for a macOS-targeted app.
- `NewsBriefingItem` (`lib/services/scheduled_news_service.dart:58`) is persisted to `AppPaths.newsBriefingsFile` and read back through `fromJson`, which tolerates missing keys via `??` defaults — so a new field needs no data migration.

## Goals / Non-Goals

**Goals:**
- Make every category label true of its contents, and make all categories reachable without a catch-all.
- Make the frequency data already being collected visible as a quick-access surface.
- Make "solid background" impossible to render with an illegible foreground in the shared badge and switch components.
- Make every briefing traceable to its original pages, without trusting the summariser to repeat URLs.

**Non-Goals:**
- Manual pinning, drag-to-reorder, or custom ranking — cumulative top 5 covers the stated need.
- Retiring `AppBadge`'s existing neutral appearance or changing dark-mode switch appearance; both already work.
- Opening links on non-macOS platforms (out of the project's target scope).
- Restructuring `ToolRegistry` itself, or renaming tool ids (they are persisted config keys).

## Decisions

### Decision 1: 常用软件 is a view, not an eighth `ToolCategory`

- **Choice**: Add it as a third `ActivityViewType` alongside `all`, `category`, `privacy`.
- **Alternatives considered**:
  - An eighth `ToolCategory` value. Rejected: it would make every tool need two `category` values (its semantic one and `frequent`), and `getByCategory` would have to special-case it. Worse, it would imply a tool's category is *usually* 常用软件, inverting the meaning — the semantic category is the attribute, 常用软件 is a projection.
  - Pinning a "常用" group at the top of the existing 全部工具 list. Rejected: it makes 全部工具 mean two things and gives no separate entry to tap.
- **Rationale**: The user confirmed a tool appears in both places. A projection, not an attribute, expresses that cleanly.

### Decision 2: Ranking = cumulative usage counts, top 5

- **Choice**: A separate `toolUsageCounts` map in `app.json`, incremented on every tool open, sorted descending with ties broken by tool id. `recentTools` keeps its existing move-to-front semantics and is *not* used for ranking.
- **How this was decided**: the first implementation reused `recentTools` and I documented that as a decision, arguing counters were not worth a persisted-shape change. The user then explicitly asked for real usage counts ("真使用次数"). Their reading of their own requirement overrides my inference from it — "按使用频率排序" says frequency, and recency is not frequency. Recorded here so the reversal is visible rather than silently rewritten.
- **Alternatives considered**:
  - Reuse `recentTools` as before. Rejected: it answers "what did I just use", not "what do I use most". A tool used twice today outranks a tool used thirty times this month if the latter was last opened an hour ago.
  - Counts with time decay (e.g. halve every 7 days). Rejected for now: decay reorders the list as time passes with no user action, which makes the entry feel unstable. Cumulative counts are predictable. Revisit only if the list proves sticky in practice.
  - Replacing `recentTools` outright. Rejected: it still has a job — choosing which tool to select at startup — and two existing tests pin its behaviour.
- **Cost, accepted**: counts never decay, so a tool used heavily once and abandoned stays ranked. Acceptable for 5 slots, and the escape hatch is that 常用软件 is one of several entries.

### Decision 3: Record usage for separate-window tools at the `selectTool` fork

- **Choice**: In the `openInNewWindow` branch of `selectTool()`, call the same usage recording (excluding private-category tools) before `openNewWindow()`.
- **Alternatives considered**:
  - Recording inside each tool's `openNewWindow()`. Rejected: it would put the same concern in three places, and `ToolDefinition` is a thin adapter that has no business owning usage analytics.
  - Recording all tools including private ones. Rejected: 常用软件 is shown without unlocking the privacy space, so ranking private tools there would leak their existence.
- **Rationale**: One fork, one call, privacy filter applied in the same place as for embedded tools.

### Decision 4: Legibility enforced in the components, not at call sites

- **Choice**: `AppBadge` derives its foreground from the background it is given; a new shared switch component pairs thumb and track. Call sites lose the ability to express an illegible combination.
- **Alternatives considered**:
  - Fix the six reported call sites individually. Rejected: this is exactly how the current state arose — 25 `AppBadge` sites and 9 switches evolved one fix at a time until three solid-background sites were wrong, two of which the user had not noticed. Patching the reports would leave the same trap for the next call site.
  - Making the components assert and throw on a bad combination. Rejected: a crash for a color pairing is disproportionate; silently correcting it is the better trade for a local single-user app.
- **Rationale**: The failure mode is "API allows an invalid combination", so the fix belongs at the API surface. This is the same reasoning that produced `onAccentSolid` in the first place — the token existed but nothing routed callers to it.

### Decision 5: Briefing sources stored, not inferred

- **Choice**: Add `sources: List<{title, url}>` to `NewsBriefingItem`, populated from the retrieval results at summary time, and render them on the briefing card. Separately give `AppMarkdownView` an optional `onTapLink`.
- **Alternatives considered**:
  - Only make markdown links clickable. Rejected: whether the summariser restates URLs is not under our control, and the requirement is that a briefing can be traced to its sources. Relying on a model to copy URLs verbatim makes the primary path probabilistic.
  - Re-fetching sources on demand. Rejected: retrieval is slow, rate-limited, and the result may have changed since the briefing was produced — it would silently change what "the source of this briefing" means.
- **Rationale**: Sources are known at write time; store them then. The markdown `onTapLink` is a complementary fix for links the model *does* emit, and costs one optional parameter.

## Risks / Trade-offs

- **[Risk] Re-categorising 6 tools breaks muscle memory** — a user who learned "笔记本 is under 系统与配置" will not find it there. → Accepted; it is the explicit request, and the new grouping is what makes each label true. 全部工具 and the search box are unaffected escape hatches.
- **[Risk] 常用软件 always shows the same 5 if the user is in a rut.** → Inherent to recency ranking; the user chose recency ordering explicitly.
- **[Risk] Correcting badge foregrounds automatically may disagree with a call site that wanted a custom pairing.** → Only fires for opaque non-neutral backgrounds; the neutral default is untouched, so the 19 neutral sites are byte-identical.
- **[Risk] `Process.run('open', url)` on a summary-injected URL.** → URLs come from the app's own retrieval results and from the configured AI provider's output. It opens the system browser, which does not execute local files; consistent with the 8 existing `open` call sites.

## Migration Plan

1. Land the token-level fixes first (`AppBadge`, switch) — they are independent of the category work and reversibly isolated.
2. Add the categories and re-assign tools; verify each category is non-empty and each label is true.
3. Add the 常用软件 view and the separate-window usage recording.
4. Add `sources` to briefings and `onTapLink` to markdown.
5. Rollback: the enum and badge changes are independent commits; reverting any one leaves the others working. No persisted data needs converting — `recentTools` shape is unchanged and `sources` defaults to empty.

## Open Questions

- Whether the 常用软件 entry should show a usage count next to each tool. Deferrable — the spec defines ranking, not decoration; adding it later does not change any requirement.
- Whether `System与配置`'s remaining four tools would be better as two smaller categories (e.g. BC 工具 / 磁盘与快捷键). Deferrable; the user asked to re-divide, and four genuinely system-scoped tools is defensible without further splitting.
