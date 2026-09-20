## Purpose

保证共享的 markdown 渲染组件在浅色与深色容器中都能给出可读的代码底色——它的默认值
必须跟随当前主题，而不是绑定在某一主题的字面量上，否则每新增一个浅色容器就要记一次
传参。

## ADDED Requirements

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
