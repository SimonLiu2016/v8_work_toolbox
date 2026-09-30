## ADDED Requirements

### Requirement: Legible foreground on a solid badge background
When a badge is given an opaque background color, its label SHALL be rendered in a foreground color that contrasts with that background, and the component SHALL derive that foreground itself rather than requiring every call site to pass a matching pair.

#### Scenario: Accent solid badge in light mode
- **WHEN** a badge is rendered with the accent solid color as its background while the light theme is active
- **THEN** the label is drawn in the theme's on-accent foreground color instead of the default secondary text color, so the text is readable rather than appearing as an unreadable solid block.

#### Scenario: Semantic solid badges in light mode
- **WHEN** a badge is rendered with a semantic solid background such as the success or error color in light mode
- **THEN** its label is rendered in the matching on-solid foreground for that semantic color.

#### Scenario: Neutral badge keeps its default foreground
- **WHEN** a badge is rendered with the default neutral background
- **THEN** its appearance is unchanged from the current one, with the default secondary text color retained.

### Requirement: Switch thumb and track remain distinguishable
Every switch control in the application SHALL render the thumb visibly distinct from the track when the switch is on, in both light and dark themes.

#### Scenario: Proxy switch in light mode
- **WHEN** a switch is rendered in the light theme with a colored track
- **THEN** the thumb is drawn in a color that contrasts with the track, so the round thumb is visible instead of the control appearing as a solid capsule.

#### Scenario: Switch appearance unchanged in dark mode
- **WHEN** the same switch is rendered in the dark theme
- **THEN** its appearance is unchanged from before this requirement, since the dark theme already rendered the thumb distinguishably.
