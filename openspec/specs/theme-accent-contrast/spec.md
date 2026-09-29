## Purpose

定义强调色（accent）系列在浅色与深色两种主题模式下的对比度契约。中性表面色不能覆盖全部 UI 角色——选中态标签、页签标题、状态徽标、等宽密码文本都需要一个"强调"身份，而这个身份必须在两种模式下都提供达标的前景/背景搭配，否则浅色模式下会出现白字落白底、浅靛蓝字落浅底等不可读组合。

## Requirements

### Requirement: Accent tokens resolve per theme mode
The accent color series (`accentText`, `accentSolid`, `onAccentSolid`, `accentSubtle`) SHALL be provided by the theme extension so that each resolves to a mode-appropriate value, rather than a shared compile-time constant that ignores the active theme.

#### Scenario: Accent foreground text in light mode
- **WHEN** an accent-colored text or icon foreground is rendered on a light surface (window `#F8FAFC`, card `#FFFFFF`, input `#F1F5F9`, or selected `#E2E8F0`)
- **THEN** it resolves to a value with a contrast ratio of at least 4.5:1 against those surfaces
- **AND** the control remains a text/icon control rather than becoming a solid fill.

#### Scenario: Accent foreground text in dark mode
- **WHEN** the same accent-colored text or icon foreground is rendered on a dark surface (window `#1E1E1E`, card `#2D2D30`, input `#3C3C3C`, or selected `#37373D`)
- **THEN** it resolves to a value with a contrast ratio of at least 4.5:1 against those surfaces.

#### Scenario: No single literal satisfies both modes
- **WHEN** a designer proposes one literal value for the accent foreground across both modes
- **THEN** it MUST be rejected when it fails the ratio in either mode, because the light-mode optimum (`#4F46E5`, 6.01 on light window) scores 2.65 on the dark window and the dark-mode optimum (`#818CF8`, 5.59 on dark window) scores 2.85 on the light window.

### Requirement: Solid accent fill carries its own foreground
Where an accent color is used as a solid fill (selected chips, indicator bars, primary surfaces), the foreground color painted on top of that fill SHALL be a dedicated `onAccentSolid` token, and the fill SHALL be dark enough in light mode to keep that foreground at or above 4.5:1.

#### Scenario: Selected chip on a light surface
- **WHEN** a chip or segment is selected in light mode and paints an accent solid fill
- **THEN** the fill resolves to the light-mode solid value and its label/icon foreground resolves to `onAccentSolid`
- **AND** the label contrast ratio against the fill is at least 4.5:1.

#### Scenario: Selected chip on a dark surface
- **WHEN** the same chip is selected in dark mode
- **THEN** the fill resolves to the dark-mode solid value, its foreground still resolves to `onAccentSolid`, and the contrast ratio remains at least 4.5:1.

### Requirement: Selected-state surfaces use theme foreground, not hardcoded white
A control whose selected-state background is a light theme surface token (selected tint, input fill, or subtle accent wash) SHALL NOT paint a hardcoded white foreground. Its foreground SHALL come from the theme so that it flips with the mode.

#### Scenario: File-type selector in folder compare
- **WHEN** the user selects a file-type chip in the folder-compare tool while in light mode
- **THEN** the chip label renders in the light-mode accent foreground rather than white on the light selected wash
- **AND** the label is legible against the chip background.

#### Scenario: Same control in dark mode is unchanged
- **WHEN** the same chip is selected in dark mode
- **THEN** its appearance is unchanged from before this capability existed, since the dark-mode accent foreground is the value that control previously hardcoded.

### Requirement: Tab bars and option tiles derive label colors from the theme
Tab bar label colors, unselected label colors, option-tile label colors, and status-badge captions SHALL derive their foreground from the accent tokens rather than naming a specific accent literal, so that no page has to special-case light mode.

#### Scenario: AI config tabs in light mode
- **WHEN** the AI configuration page renders its tab bar in light mode
- **THEN** the selected tab label resolves to the light-mode accent foreground with a contrast ratio of at least 4.5:1 against the page surface.

#### Scenario: All tab bars agree
- **WHEN** any tab bar in the application is rendered in either mode
- **THEN** every tab bar resolves the selected label through the same accent token, so no single page diverges from the rest.

### Requirement: Static accent references are excluded from widget code
The widget source tree SHALL NOT contain compile-time references to the static accent constants. The theme definition module that supplies both presets is the only permitted reference point, matching the rule already established for the neutral surface tokens.

#### Scenario: Scan finds no widget-layer accent reference
- **WHEN** the source tree is scanned for references to the static accent constants (`AppTheme.accent`, `AppTheme.accentLight`, `AppTheme.accentDark`, `AppTheme.accentSubtle`)
- **THEN** no widget-layer file contains such a reference
- **AND** the scan is enforced by the same guard used for the neutral surface tokens.

### Requirement: Contrast contract is regression-tested
The minimum contrast ratios for every accent role in both modes SHALL be asserted in an automated test, so that a future palette adjustment cannot silently reintroduce an illegible combination.

#### Scenario: Test fails on a regressed token
- **WHEN** any accent token's value is changed such that its role's ratio falls below the threshold (4.5:1 for text and on-solid foregrounds, 3.0:1 for icons)
- **THEN** the contrast contract test fails and names the token and mode at fault.
