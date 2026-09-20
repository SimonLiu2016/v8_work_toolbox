# disk-analyzer Delta

## MODIFIED Requirements

### Requirement: Project build artifact discovery with manifest gating

The slimmer SHALL discover build artifacts inside project trees as a fourth scan tier. The scan MUST operate in two layers: a shallow manifest-discovery layer that identifies project roots by build-manifest signals (`.git`, `package.json`, `pubspec.yaml`, `build.gradle`, `build.gradle.kts`, `Podfile`, `CMakeLists.txt`, `go.mod`, `xcodeproj`, `pom.xml`, `Cargo.toml`) within a bounded depth of 5 from the user's home directory, and a pruned artifact-collection layer that only walks inside identified project roots. The discovery layer MUST prune package-manager cache directories (`.pub-cache`, `.npm`, `.yarn`, `.cache`, `.cargo`, `.rustup`, `.local`) which are download caches rather than user projects, and MUST prune `~/Applications` in this tier (application bundles are scanned by the orphaned-app tier, not by project-artifact discovery). Manifest gating applies to any other signal as well: a directory is a valid candidate only when it sits inside an identified project root. Artifacts MUST NOT be discovered by a whole-disk walk of the home directory.

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

#### Scenario: Watchlist supplements automatic discovery
- **WHEN** user adds an extra project root through the settings retained from the previous build-artifact cleaner
- **THEN** artifacts inside that root are discovered and aggregated alongside automatically discovered roots, without requiring the root to have a recognized build manifest
