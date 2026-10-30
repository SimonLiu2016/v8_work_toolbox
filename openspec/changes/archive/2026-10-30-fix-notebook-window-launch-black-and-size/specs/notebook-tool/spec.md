## MODIFIED Requirements

### Requirement: Fixed-Width Column Layout and Launch Sizing
The standalone notebook window SHALL provide consistent, non-stretching column widths for navigation and fill the current display's visible work area upon opening.

#### Scenario: Fixed sidebar and note list dimensions
- **WHEN** the notebook window is resized or maximized
- **THEN** the leftmost notebook navigation column remains at a fixed width of 240px, the center note list column remains at a fixed width of 320px, and the right-hand note editor flexibly fills all remaining horizontal space.

#### Scenario: Maximizing notebook sub-window on creation
- **WHEN** the user opens the standalone notebook window
- **THEN** the window fills the active screen's visible work area (excluding system dock and menu bar) at its first appearance, without first appearing at a smaller size and then resizing.

#### Scenario: Window position matches its size at first appearance
- **WHEN** the notebook window becomes visible for the first time
- **THEN** it is already at the work-area size and position described above, rather than appearing at a small default size in a screen corner and later jumping.
