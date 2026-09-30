## Purpose

Provides a frequency-ranked quick-access surface for the user's most-used tools, independent of their semantic category, so the tools a user actually opens daily are reachable without hunting through category lists.

## ADDED Requirements

### Requirement: Frequently used entry ranked by usage frequency
The application SHALL expose a "常用软件" entry that lists the user's top 5 tools by usage frequency, ordered most-used first.

#### Scenario: Entry reflects the most used tools first
- **WHEN** the user has opened several tools and then opens the 常用软件 entry
- **THEN** the listed tools are ordered by recency-weighted usage frequency with the most used first, and no more than 5 entries are shown.

#### Scenario: Tool may also belong to its semantic category
- **WHEN** a tool appears in 常用软件
- **THEN** it also remains listed under its semantic category, because 常用软件 is a quick-access surface rather than a relocation.

### Requirement: Entry hidden without usage history
The 常用软件 entry SHALL NOT be shown when the user has no tool usage history.

#### Scenario: Fresh install or cleared history
- **WHEN** the user has never opened any non-private tool
- **THEN** no 常用软件 entry is rendered in the activity bar, and all other entries remain unaffected.

### Requirement: Usage recorded for both embedded and separate-window tools
Opening a tool SHALL count toward its usage frequency regardless of whether the tool is embedded in the main window or opened in its own separate window.

#### Scenario: Separate-window tool usage is recorded
- **WHEN** the user opens a tool that launches in its own window (for example the notebook, password vault, or ops tool)
- **THEN** that tool's usage frequency is recorded just as an embedded tool's would be, so it can appear in 常用软件.

#### Scenario: Private tools excluded from frequency ranking
- **WHEN** a private-category tool is opened while the privacy space is unlocked
- **THEN** it is not recorded toward 常用软件, since that surface is visible without unlocking the privacy space.
