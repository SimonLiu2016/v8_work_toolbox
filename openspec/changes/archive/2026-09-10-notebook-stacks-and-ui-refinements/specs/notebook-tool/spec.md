## ADDED Requirements

### Requirement: Hierarchical Notebook Stack Navigation
The notebook tool SHALL organize notebooks into collapsible stack groups according to their parent stack metadata.

#### Scenario: Displaying collapsible notebook stack groups
- **WHEN** the user opens the notebook navigation pane
- **THEN** notebooks sharing the same stack are grouped under an accordion header showing the stack name and notebook count, with collapse/expand toggle controls.

#### Scenario: Filtering notes by stack or individual notebook
- **WHEN** the user clicks on a notebook stack header
- **THEN** the note list displays all notes belonging to all notebooks within that stack.
- **WHEN** the user clicks on a specific notebook under a stack
- **THEN** the note list displays only notes belonging to that specific notebook.

#### Scenario: Automatic stack backfill on startup
- **WHEN** the notebook database initializes and notebooks lack stack metadata
- **THEN** the system matches existing notebooks against the local Evernote database store and updates their stack values without requiring re-import.

### Requirement: Fixed-Width Column Layout and Launch Sizing
The standalone notebook window SHALL provide consistent, non-stretching column widths for navigation and maximize to the display workspace upon opening.

#### Scenario: Fixed sidebar and note list dimensions
- **WHEN** the notebook window is resized or maximized
- **THEN** the leftmost notebook navigation column remains at a fixed width of 240px, the center note list column remains at a fixed width of 320px, and the right-hand note editor flexibly fills all remaining horizontal space.

#### Scenario: Maximizing notebook sub-window on creation
- **WHEN** the user opens the standalone notebook window
- **THEN** the window is automatically maximized to fill the active screen's visible work area (excluding system dock and menu bar).

### Requirement: Compact Single-Row Editor Toolbar
The rich-text note editor SHALL display a streamlined, single-row compact toolbar to maximize vertical writing canvas space.

#### Scenario: Rendering compact toolbar
- **WHEN** the note editor view is displayed
- **THEN** the toolbar renders in a single horizontal row with a height not exceeding 36px, smaller 16px icons, and subtle divider borders, scrolling horizontally when the window width is constrained.
