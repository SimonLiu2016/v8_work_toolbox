# disk-analyzer Delta

## MODIFIED Requirements

### Requirement: Project build artifact discovery with manifest gating

The slimmer SHALL discover build artifacts inside project trees as a fourth scan tier. The scan MUST operate in two layers: a shallow manifest-discovery layer that identifies project roots by build-manifest signals (`.git`, `package.json`, `pubspec.yaml`, `build.gradle`, `build.gradle.kts`, `Podfile`, `CMakeLists.txt`, `go.mod`, `xcodeproj`, `pom.xml`, `Cargo.toml`) within a bounded depth of 5 from the user's home directory, and a pruned artifact-collection layer that only walks inside identified project roots. The discovery layer MUST prune package-manager cache directories (`.pub-cache`, `.npm`, `.yarn`, `.cache`, `.cargo`, `.rustup`, `.local`) which are download caches rather than user projects, and MUST prune `~/Applications` in this tier (application bundles are scanned by the orphaned-app tier, not by project-artifact discovery). Manifest gating applies to any other signal as well: a directory is a valid candidate only when it sits inside an identified project root. Artifacts MUST NOT be discovered by a whole-disk walk of the home directory.

The watchlist supplements automatic discovery but MUST NOT absorb it. When a watchlist entry contains automatically discovered project roots beneath it, the watchlist entry itself MUST be discarded and the discovered roots preserved. A watchlist entry is only itself a project root when no automatically discovered root lies beneath it. The watchlist MUST NOT function as a parent prefix that swallows nested roots.

#### Scenario: Project artifact tier surfaces project-tree artifacts
- **WHEN** user explicitly starts a scan and the fourth tier completes
- **THEN** project-tree build artifacts (`node_modules`, `build`, `dist`, `.gradle`, `.dart_tool`, `.git` 无关的产物目录等) are listed as reclaimable candidates and are grouped under a project-build-artifact category distinct from global shared caches

#### Scenario: Maven and Rust projects without .git are discovered
- **WHEN** a project root contains `pom.xml` or `Cargo.toml` but no `.git`
- **THEN** the root is identified as a project root and its `target` artifact is collected

#### Scenario: Package-manager cache directories are not project roots
- **WHEN** the home directory contains `.pub-cache` with thousands of `pubspec.yaml` files, `.npm` with thousands of `package.json` files, or `.cargo` with `Cargo.toml` files
- **THEN** these cache directories are pruned from discovery and do not contribute project roots

#### Scenario: Applications directory is not scanned for build artifacts
- **WHEN** the fourth tier runs
- **THEN** `~/Applications` is pruned from project-root discovery, but the orphaned-app-remnant tier (which inspects `~/Library/Application Support`, `~/Library/Caches`, and `~/Library/Containers`) is unaffected and still detects remnants of apps installed in `~/Applications`

#### Scenario: Manifest gating excludes name collisions outside project roots
- **WHEN** the home directory contains a `node_modules` directory that is not inside any directory identified as a project root (for example a stray top-level `~/node_modules` next to a `package-lock.json`)
- **THEN** that directory does not appear as a cleanup candidate

#### Scenario: The home directory itself is never a project root
- **WHEN** a build-manifest signal exists directly in the user's home directory (for example a stray `~/package.json`)
- **THEN** the home directory itself is not reported as a project root, and the other project roots discovered beneath it are all preserved rather than being absorbed by it

#### Scenario: Discovery budget is explicit, never silent
- **WHEN** a project root exceeds its per-root time budget or its artifact-count budget during collection
- **THEN** the resulting item is marked as "扫描超时 / 未完整" with the discovered portion still shown, and the system does not silently omit the remainder

#### Scenario: Watchlist supplements without absorbing discovered roots
- **WHEN** user adds an extra project root through the settings retained from the previous build-artifact cleaner, and that root contains automatically discovered project roots beneath it
- **THEN** the automatically discovered roots are each preserved as their own candidate items, the broad watchlist entry itself is not reported as a project root, and no discovered root is absorbed by the watchlist entry

#### Scenario: Watchlist entry is a root only when it has no discovered descendants
- **WHEN** user adds an extra project root that contains no automatically discovered project roots beneath it (for example a project lacking a recognized build manifest)
- **THEN** artifacts inside that root are discovered and aggregated, without requiring the root to have a recognized build manifest

### Requirement: Project-root aggregation and technology-stack grouping

Each identified project root MUST be presented as a single aggregated candidate item; the item's subtitle MUST show the total number of artifact directories inside that root plus a per-technology composition summary (for example "23 个产物目录 · node_modules ×5 / build ×8"). The item MUST be expandable to reveal the per-directory detail (path and size). Only roots with at least one artifact hit and a total size of at least 10 MB are presented in the list. List rows MUST be grouped by technology stack, and the grouping MUST include a Maven / Java group derived from the `pom.xml` signal, alongside the Flutter/Dart, Node, and Gradle/Android groups. Roots with no recognized manifest signal MUST fall into a clearly-labeled catch-all group rather than being silently omitted.

#### Scenario: Aggregation prevents list explosion
- **WHEN** a machine contains several hundred identified project roots
- **THEN** the candidate list contains one item per qualifying root rather than one row per matched artifact directory

#### Scenario: Composition summary and expandable detail
- **WHEN** user expands an aggregated project root item
- **THEN** the user sees the individual artifact directories inside that root with their paths and sizes

#### Scenario: Threshold filters small roots
- **WHEN** a project root contains artifact directories whose combined size is below 10 MB
- **THEN** it is not shown in the list, and the aggregated freed-space total excludes it

#### Scenario: Technology-stack grouping rows
- **WHEN** user views the project artifact results after the fourth tier completes
- **THEN** results are grouped by technology stack, each group showing the number of project roots and the aggregated reclaimable size

#### Scenario: Maven project is grouped under Maven / Java, not the catch-all group
- **WHEN** a project root contains `pom.xml` and a `target` artifact directory
- **THEN** the root is grouped under the Maven / Java group rather than the catch-all group, and the Maven / Java group is visible in the technology-stack filter chips

#### Scenario: Catch-all group is explicitly labeled
- **WHEN** a project root has artifact directories but no recognized manifest signal
- **THEN** it is grouped under an explicitly-labeled catch-all group, and is not silently omitted from the results
