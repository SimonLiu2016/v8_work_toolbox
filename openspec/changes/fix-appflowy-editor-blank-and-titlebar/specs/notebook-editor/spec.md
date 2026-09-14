## ADDED Requirements

### Requirement: Standalone editor canvas layout and empty space focus
The notebook editor SHALL mount the AppFlowy editor component inside a bounded layout container with native scrolling and responsive padding, and SHALL ensure that tapping any empty area of the editor canvas focuses the document.

#### Scenario: Editor canvas renders with bounded dimensions
- **WHEN** user opens any note (empty or existing)
- **THEN** the editor body beneath the toolbar renders with full visible height, displays existing content with high contrast, and does not collapse or trigger unbounded layout exceptions.

#### Scenario: Tap on empty canvas focuses editor
- **WHEN** user clicks on any empty area below or around the text in the editor
- **THEN** the editor gains focus, the cursor appears at the appropriate document position, and keyboard inputs are captured immediately.

### Requirement: Seamless window titlebar and header integration
The notebook editor and single-note sub-windows SHALL render top navigation and export bars with background styling and top safe margins that integrate cleanly with the macOS transparent titlebar.

#### Scenario: Unified window header on macOS
- **WHEN** a user views the notebook page or single-note editor window on macOS
- **THEN** the top navigation area provides sufficient top clearance for window control buttons without dark border clipping or background color mismatch.
