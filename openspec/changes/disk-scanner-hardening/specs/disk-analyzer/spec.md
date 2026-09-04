## MODIFIED Requirements

### Requirement: Orphaned app remnant detection
The analyzer SHALL match directories in `~/Library/Application Support`, `~/Library/Caches`, and `~/Library/Containers` against installed applications in `/Applications` and `~/Applications` using multi-layered verification: Bundle ID exact match, known alias mapping, bidirectional substring match, and recency-based safety downgrade. Items not matching any layer SHALL default to "caution" safety rating, MUST NOT default to "safe".

#### Scenario: Identifying uninstalled software remnants
- **WHEN** user inspects the Application Remnants section
- **THEN** folders belonging to removed apps are highlighted with estimated size, last modified date, and flagged as recommended for removal.

#### Scenario: Active application not misidentified
- **WHEN** an Application Support directory belongs to an installed app whose .app name differs from the directory name (e.g., `Code` → `Visual Studio Code.app`)
- **THEN** the directory is matched via Bundle ID or alias mapping and excluded from orphan candidates.

#### Scenario: Recently modified directory safety downgrade
- **WHEN** an unmatched directory was modified within the last 30 days
- **THEN** its safety rating is downgraded to "caution" or "danger" based on recency, and it is not auto-selected for cleanup.

### Requirement: Multi-version runtime and IDE management
The system SHALL detect parallel installations and historical upgrade versions of development environments (Python, Node.js, JDK) and IDEs (JetBrains products, Android Studio), displaying individual version sizes with directory source labels (configuration vs cache) and allowing granular removal of obsolete versions.

#### Scenario: Detecting obsolete JetBrains versions
- **WHEN** the scan finds IntelliJ IDEA configuration and cache folders across multiple release years (e.g. 2022.3, 2023.2, 2024.2)
- **THEN** older unused versions are grouped and pre-selected for cleanup while preserving the most recent active version.

#### Scenario: JetBrains directory source disambiguation
- **WHEN** the scan finds both `~/Library/Application Support/JetBrains/IntelliJIdea2026.2` and `~/Library/Caches/JetBrains/IntelliJIdea2026.2`
- **THEN** each entry displays a source label in its title (e.g., "IntelliJIdea 2026.2（配置）" vs "IntelliJIdea 2026.2（缓存）") so the user can distinguish them.

### Requirement: Interactive cleanup selection
The cleanup candidate list SHALL support manual checkbox toggling for every item. The scan result list MUST be stored as a mutable collection, MUST NOT use `List.unmodifiable`.

#### Scenario: Manual checkbox toggle
- **WHEN** user clicks a checkbox on any cleanup candidate item
- **THEN** the item's selection state toggles immediately, and the total reclaimable size in the action button updates accordingly.

#### Scenario: User override persistence
- **WHEN** user manually deselects an item that was auto-selected as "safe to clean"
- **THEN** the deselection decision is persisted to configuration, and the item is automatically deselected on future scans.
