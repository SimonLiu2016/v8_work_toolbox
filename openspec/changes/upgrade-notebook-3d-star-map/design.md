## Context

See `proposal.md` for motivation.
The existing `KnowledgeGraphView` relies on 2D deterministic force-directed layout and hides all labels once the node count exceeds 12. To deliver a visually striking experience matching modern AI knowledge maps (such as Kimi's star map), we replace the 2D layout with a 3D spherical constellation engine supporting ambient rotation, gesture orbit controls, and core node title labels.

## Goals / Non-Goals

**Goals:**
- Render notes in a 3D spherical space with genuine depth perspective, depth cueing, and z-sorting.
- Maintain a silky smooth ambient vertical rotation at ~60fps that can be dragged, pitched, and yawed with mouse gestures.
- Display permanent glowing title labels on the most central hub notes (top 8~12 by connection degree, plus asset notes).
- Implement depth culling so that titles and halo nodes on the back side of the celestial sphere gracefully fade out, preventing clutter.
- Adopt a deep cosmic visual aesthetic with subtle starry dust and glowing constellation filaments.

**Non-Goals:**
- Using heavy external C++/OpenGL or WebGL engine plugins (pure Flutter canvas mathematics provides cross-platform stability, minimal memory footprint, and native performance).
- Modifying underlying database schemas (`notes`, `note_links`).

## Decisions

### Decision 1: 3D Fibonacci Sphere with Degree Clustering
- **Decision**: Position nodes in a 3D coordinate frame $(X, Y, Z)$ using a Fibonacci spherical distribution. The sphere radius scales with node count ($R \approx 140 \sim 220$), with high-degree nodes slightly offset towards the prominent visual plane.
- **Rationale**: Eliminates node collision in 2D and provides uniform spatial density across the celestial sphere.

### Decision 2: Native 3D Perspective Projection & Z-Sorting
- **Decision**: Apply Euler rotation matrices ($\theta_x, \theta_y$) and perspective projection:
  $$Scale = \frac{D}{D + Z'}, \quad ScreenX = CenterX + X' \cdot Scale, \quad ScreenY = CenterY + Y' \cdot Scale$$
  Before rendering each frame, sort nodes and edges by their transformed $Z'$ coordinate so near objects cleanly occlude far objects.
- **Rationale**: Delivers authentic 3D depth with zero binary dependencies.

### Decision 3: Cosmic Visual Styling & Shimmering Ambient Glow
- **Decision**:
  - Background: Gradient from `#090D16` to `#111827`.
  - Background Star Dust: 60 deterministic micro-stars sprinkled across the canvas.
  - Nodes: Multi-layer radial glow for core nodes; asset notes tinted in golden amber; regular notes in celestial cyan/blue.
  - Constellations: Semi-transparent cyan lines (`#38BDF8`) with stroke opacity modulated by depth.

### Decision 4: Core Hub Nodes Always-On Labels with Back-Face Fading
- **Decision**: Calculate node connection degrees (`degree = outgoing + incoming`). The top $K$ nodes (up to 10) are marked as core nodes. When $Z' > -30$ (front half of sphere), their labels are rendered with glowing translucent background capsules. When rotating towards the back ($Z' \le -30$), the labels fade to 0 opacity.
- **Rationale**: Ensures key knowledge anchors are immediately readable without turning the screen into an unreadable mess of overlapping text.

### Decision 5: Ambient Rotation & Interactive Orbit Controller
- **Decision**: Drive rotation using an `AnimationController` running continually at $\approx 0.003$ rad/frame. On `onPanUpdate`, pause the auto-timer and directly increment $\theta_x, \theta_y$. On `onPanEnd`, apply slight inertia and resume auto-rotation after 1.5 seconds of inactivity.

## Risks / Trade-offs

- **[Risk] High CPU load during continuous animation** → Mitigation: 3D math on 50~200 nodes is trivial (a few hundred floating-point operations per frame); CustomPainter handles this easily at < 2% CPU usage.
- **[Risk] Hit-testing accuracy on rotating 3D nodes** → Mitigation: `_hitTest` uses projected $(ScreenX, ScreenY)$ with depth-scaled radius, favoring nodes with higher $Z'$ (nearer to camera).
