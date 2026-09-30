# shared-markdown-theme-contrast

## Purpose

保证共享的 markdown 渲染组件在浅色与深色容器中都能给出可读的代码底色——它的默认值
必须跟随当前主题，而不是绑定在某一主题的字面量上，否则每新增一个浅色容器就要记一次
传参。

## Requirements

### Requirement: Code background follows the active theme brightness
The shared markdown rendering component SHALL derive its default code background from the
active theme's brightness rather than a fixed dark value, so that inline code spans and
fenced code blocks remain legible on both light and dark surfaces without every call site
having to override it.

#### Scenario: Default on a dark surface
- **WHEN** the markdown component is rendered inside a dark-themed container and the caller does not override the code background
- **THEN** the code background resolves to the dark container's expected surface color
- **AND** code text remains legible against it.

#### Scenario: Default on a light surface
- **WHEN** the markdown component is rendered inside a light-themed container (e.g. the notebook's ask-my-notes panel) and the caller does not override the code background
- **THEN** the code background resolves to a light neutral rather than a dark gray
- **AND** the near-black code text stays legible, with no dark box artifact over the light background.

#### Scenario: Explicit override still wins
- **WHEN** a caller passes an explicit code background color
- **THEN** that color is used as-is regardless of theme brightness
- **AND** existing dark-surface callers keep their current appearance unchanged.

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
