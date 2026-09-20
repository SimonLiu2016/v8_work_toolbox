# notebook-tool Delta

## ADDED Requirements

### Requirement: Ask-my-notes panel fits its fixed narrow column
The ask-my-notes panel SHALL lay out its header and answer area within its fixed narrow
column width without clipping or overflowing any control. Text that cannot fit SHALL be
removed or made to ellipsize rather than pushing adjacent controls out of the panel.

#### Scenario: Header controls fully visible at the panel's fixed width
- **WHEN** the ask-my-notes panel is open at its fixed column width
- **THEN** the panel title and the clear-conversation control are both fully visible
- **AND** no control is clipped, half-hidden, or rendered outside the panel bounds.

#### Scenario: Header stays correct once a conversation exists
- **WHEN** the panel has one or more question/answer turns (so the clear control is shown)
- **THEN** the header still fits without overflow
- **AND** removing all turns hides the clear control without leaving an empty gap that changes the layout.

#### Scenario: Marked text in answers is legible
- **WHEN** an answer contains inline code spans or fenced code blocks
- **THEN** their background contrasts with the panel's light surface and the text remains readable
- **AND** no dark-gray box artifact appears over the light background.
