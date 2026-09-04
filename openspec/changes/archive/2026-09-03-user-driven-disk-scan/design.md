## Context

Cold application boot suffered from several seconds of black screen because `IndexedStack` synchronously initialized all registered tools at launch, while `SmartDiskSlimmerPage` automatically began recursive disk I/O in its `initState`.

## Goals / Non-Goals

**Goals:**
- Eliminate cold-start frame blocking (target startup time < 100ms).
- Introduce an idle / ready state in `SmartDiskSlimmerPage` with volume overview and a prominent "🚀 开始全盘智能分析" action.
- Implement lazy loading in `AppShell`'s `IndexedStack` so tools only instantiate their widgets and state when first navigated to.

**Non-Goals:**
- Removing tools from memory once loaded (tools remain mounted in `IndexedStack` once visited to preserve live state).

## Decisions

### 1. SmartDiskSlimmerPage State Machine
- `isIdle`: initial state, `_items` is empty, no scan in progress. Shows Macintosh HD usage bar and an aesthetic launch card with feature badges.
- `isScanning`: triggered by user clicking the primary button.
- `isCompleted`: shows filter chips, candidate list, AI diagnostics, and Trash actions.

### 2. AppShell Lazy Loaded IndexedStack
- Maintain `Set<int> _activatedToolIndices = {initialIndex}`.
- In `IndexedStack.children`:
  ```dart
  allTools.asMap().entries.map((entry) {
    final idx = entry.key;
    final tool = entry.value;
    if (_activatedToolIndices.contains(idx)) {
      return tool.buildPage(context);
    }
    return const SizedBox.shrink();
  }).toList()
  ```
- When `_selectedToolId` changes, insert the target index into `_activatedToolIndices`.
