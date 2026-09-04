## Context

Users accumulate gigabytes of hidden caches, orphaned app data, and multiple outdated runtime/IDE versions on macOS. See `proposal.md` for motivation. We design a staged scanning engine, heuristic multi-version tracker, and AI metadata diagnostics service integrated into V8WorkToolbox.

## Goals / Non-Goals

**Goals:**
- Provide progressive scan results within 3 seconds using tiered heuristics.
- Accurately identify orphaned directories whose parent apps have been deleted from `/Applications`.
- Group and present multi-version IDEs (JetBrains, Android Studio) and runtimes (Python, Node, Java).
- Default to `NSWorkspace.shared.recycle` for 100% reversible file recycling.
- Automate batch AI diagnostics on ambiguous items using metadata only.

**Non-Goals:**
- Tampering with APFS read-only system snapshots (`/System`, `/usr/bin`) protected by System Integrity Protection (SIP).
- Reading or uploading sensitive file contents to AI services.

## Decisions

### 1. Tiered Scanning Architecture
- **Decision**: Break scan execution into three distinct progressive stages:
  - `Tier 1 (Instant)`: Direct probing of `~/Library/Developer/Xcode/DerivedData`, `~/Library/Caches`, `~/Downloads` large binaries (`.dmg`, `.pkg`, `.iso`).
  - `Tier 2 (Runtimes & IDEs)`: Scan known version managers (`~/.pyenv/versions`, `~/.nvm/versions`, `/Library/Java/JavaVirtualMachines/`, `~/Library/Application Support/JetBrains/`).
  - `Tier 3 (Orphan Deep Scan)`: List all app bundle IDs in `/Applications` and `~/Applications`, then scan `~/Library/Containers` and `~/Library/Application Support` for unreferenced items.
- **Alternatives Considered**: Single monolithic deep scan. Rejected because scanning whole disk synchronously locks UI and frustrates users.

### 2. Multi-Version Detection Engine
- **Decision**: Implement specialized scanners:
  - `JetBrainsScanner`: Match regex `IntelliJIdea(\d{4}\.\d+)`, `PyCharm(\d{4}\.\d+)`, `AndroidStudio(\d{4}\.\d+)` in both Application Support and Caches. Mark newest version as "Active", older as "Obsolete".
  - `PythonScanner`: Probe `/Library/Frameworks/Python.framework/Versions`, `~/.pyenv/versions`, `~/miniconda3/envs`.
  - `NodeScanner`: Probe `~/.nvm/versions/node/` and `~/.local/share/fnm/currents/`.
- **Alternatives Considered**: Generic folder size sorter. Rejected because without semantic version understanding, users cannot tell which version is safe to delete.

### 3. Reversible Trash Disposal Bridge
- **Decision**: In `AppDelegate.swift`, expose MethodChannel method `recyclePaths(paths: [String]) -> Bool`. It converts file paths to `[URL]` and calls `NSWorkspace.shared.recycle(urls)`.
- **Alternatives Considered**: Dart `Directory.delete(recursive: true)`. Rejected because physical deletion is irreversible and risks catastrophic data loss.

### 4. Privacy-Preserving AI Diagnostics
- **Decision**: When an item has no known vendor mapping and size > 500 MB, construct an AI payload containing ONLY:
  ```json
  {
    "relativePath": "~/Library/Application Support/vendor_hash_xyz",
    "totalSizeBytes": 1542891000,
    "fileCount": 84,
    "dominantExtensions": [".tmp", ".cache", ".dat"],
    "lastModifiedDaysAgo": 480
  }
  ```
  The payload is sent to `AiService.instance.chat(slot: 'text', messages: ...)` requesting structured JSON recommendations (safety tier, reasoning, app association).
- **Alternatives Considered**: Transmitting file contents. Strictly rejected due to user privacy and performance constraints.

## Risks / Trade-offs

- **[Risk]** macOS Full Disk Access (FDA) permission requirements on certain `~/Library` subfolders.
  → **Mitigation**: Handle `PathAccessException` gracefully, skip permission-denied directories without crashing, and display informational banner suggesting FDA if scan coverage is restricted.
- **[Risk]** Active background processes accessing files during recycle.
  → **Mitigation**: `NSWorkspace.shared.recycle` handles file locking natively and surfaces system alerts if files are currently open.
