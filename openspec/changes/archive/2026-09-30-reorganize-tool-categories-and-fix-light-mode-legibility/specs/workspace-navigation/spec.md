## MODIFIED Requirements

### Requirement: Activity bar and tool panel split navigation
The workspace SHALL divide navigation into an Activity Bar and a Tool Panel, and the content container SHALL lazily instantiate tool views on demand so tools are only mounted when navigated to by the user. The Activity Bar SHALL list every semantic tool category plus, when the user has usage history, the frequency-ranked 常用软件 surface.

#### Scenario: Switching tool categories
- **WHEN** user clicks a category icon in the Activity Bar
- **THEN** the Tool Panel immediately switches to show only the tools assigned to that category, with search filtering scoped to the active view.

#### Scenario: Every semantic category is reachable
- **WHEN** user views the Activity Bar
- **THEN** each semantic tool category is listed exactly once, including the categories covering AI, notes, and operations, so no category is reachable only by scrolling a long list inside one catch-all entry.

#### Scenario: Category membership is semantically consistent
- **WHEN** the user opens the 系统与配置 category
- **THEN** it contains only tools whose purpose is system configuration or maintenance, and not tools that belong to AI, note-taking, or operations categories.

#### Scenario: Collapsing tool panel
- **WHEN** user toggles panel collapse or double-clicks the separator
- **THEN** the Tool Panel folds into an icon-only compact mode (~50px) to give maximum screen width to the tool content area.

#### Scenario: Lazy tool mounting
- **WHEN** the application starts up
- **THEN** only the initially active tool view is instantiated in the content stack, preventing unselected heavy tools from blocking startup frames.
