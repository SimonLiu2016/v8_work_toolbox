## ADDED Requirements

### Requirement: Knowledge Graph Viewport Clipping and Boundary Containment
The knowledge star map view SHALL constrain all rendered visual elements—including 3D celestial nodes, orbital edges, glowing halos, star dust particles, and persistent text capsule labels—strictly within the bounds of its layout viewport. No painted element SHALL spill over, bleed, or render outside the star map container into adjacent panels (such as the main note editor or list views).

#### Scenario: Visual elements clipped at boundary
- **WHEN** 3D celestial nodes rotate towards the boundary edges or text labels extend outward near the side margins
- **THEN** all rendered graphics outside the star map bounding box are physically clipped
- **AND** the adjacent note editor area remains completely pristine with zero visual overflow.

#### Scenario: Safe padding and margin clamping for text labels
- **WHEN** a core hub node or hovered node is positioned near the left or right margin of the star map viewport
- **THEN** the text capsule label's horizontal coordinates are clamped with safe edge insets
- **AND** text labels do not get prematurely chopped while still adhering to the viewport bounds.
