## ADDED Requirements

### Requirement: Knowledge Graph Rotation Speed and Focus Interaction
The knowledge star map SHALL perform slow, ambient 3D rotation at a serene pace (approximately 0.0010 to 0.0015 radians per frame) to prevent visual distraction. When the user interacts by clicking any celestial node to view or open a note, the star map SHALL immediately pause its rotation to keep the selected node and its neighborhood stationary. When the mouse pointer leaves the star map container boundaries, the star map SHALL automatically resume its ambient rotation.

#### Scenario: Gentle ambient rotation speed
- **WHEN** the knowledge star map is displayed in idle state with auto-rotation enabled
- **THEN** the celestial sphere rotates at approximately 0.0012 radians per animation frame
- **AND** the motion feels smooth, tranquil, and non-dizzying.

#### Scenario: Node click pauses rotation
- **WHEN** the user clicks on a celestial node in the star map
- **THEN** the star map pauses automatic rotation immediately
- **AND** the selected node and its orbital connections remain fixed at their current 3D perspective.

#### Scenario: Mouse exit resumes rotation
- **WHEN** the user moves the mouse cursor outside the boundary of the star map container
- **THEN** the star map clears hover indicators and automatically resumes ambient 3D rotation.
