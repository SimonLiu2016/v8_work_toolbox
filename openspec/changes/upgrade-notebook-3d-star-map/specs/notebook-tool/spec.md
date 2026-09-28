# notebook-tool Delta

## ADDED Requirements

### Requirement: 3D Spherical Perspective Knowledge Star Map
The notebook tool SHALL render note relationship networks as a 3D spherical star map with perspective depth, continuous ambient rotation, interactive 3D orbit manipulation, and persistent title labels on core hub nodes.

#### Scenario: Displaying 3D star map in deep space visual theme
- **WHEN** the user opens the knowledge graph view
- **THEN** the system renders a cosmic canvas featuring deep-space background gradients, twinkling background star dust, glowing celestial note nodes, and semi-transparent depth-attenuated constellation edges.

#### Scenario: Ambient slow rotation of the star map
- **WHEN** the knowledge star map is idle without user touch or drag interaction
- **THEN** the system rotates the entire 3D star cluster smoothly around its vertical axis at a subtle ambient velocity.

#### Scenario: User gesture manipulation in 3D space
- **WHEN** the user drags across the star map canvas
- **THEN** ambient rotation temporarily pauses, the viewpoint rotates freely across pitch and yaw angles according to the drag vector, and smoothly resumes ambient rotation after interaction ends.

#### Scenario: Always-on title labels for core hub nodes with depth culling
- **WHEN** the star map contains note nodes
- **THEN** the top connected hub nodes (ranked by degree) and asset notes display persistent title labels when facing the camera, while fading labels out when rotated behind the celestial sphere to prevent visual overlap.

#### Scenario: Hover and click interactions on star map nodes
- **WHEN** the user hovers over any star node
- **THEN** the hovered node scales up with an intense halo, displays its full title, and highlights its connected edges.
- **WHEN** the user clicks on the star node
- **THEN** the system triggers note navigation and opens the corresponding note in the main editor.
