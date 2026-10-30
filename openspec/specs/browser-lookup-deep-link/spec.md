# browser-lookup-deep-link Specification

## Purpose
Carries the user's expressed intent from the browser companion into the desktop app — "analyse this word with AI" and "add this word to my vocabulary book" — without forcing an intermediate dictionary lookup the user did not ask for, and opens its windows at sizes suited to their content rather than filling the screen.
## Requirements
### Requirement: Deep link carries the AI-analysis intent
The desktop app's lookup deep link SHALL accept an explicit mode so that a request originating from "ask AI" does not perform a dictionary lookup first.

#### Scenario: mode=ai skips the dictionary
- **WHEN** the desktop app receives `v8toolbox://lookup?text=<word>&mode=ai`
- **THEN** the lookup window opens and goes straight to AI analysis for that word, and no dictionary result or "not found in dictionary" state is shown before it.

#### Scenario: omitted mode keeps dictionary-first behaviour
- **WHEN** the desktop app receives `v8toolbox://lookup?text=<word>` with no mode parameter
- **THEN** it behaves as before this capability existed: dictionary lookup first, with the AI option offered afterwards, so that existing callers are unaffected.

#### Scenario: unknown mode falls back to dictionary-first
- **WHEN** the deep link carries a mode value the app does not recognise
- **THEN** it is treated as the default dictionary-first behaviour rather than as an error.

### Requirement: Add-to-vocabulary is a direct action, not a window
The desktop app SHALL provide a deep link that adds a word to the vocabulary book without opening any window and without querying the dictionary.

#### Scenario: vocab deep link adds the word
- **WHEN** the desktop app receives `v8toolbox://vocab?text=<word>`
- **THEN** the word is added to the vocabulary book, no window is opened, and no dictionary lookup is performed.

#### Scenario: adding an already-present word is a no-op
- **WHEN** the received word already exists in the vocabulary book
- **THEN** no duplicate entry is created and the user is not shown an error.

### Requirement: Sub-window sizes are declared per purpose
Each kind of sub-window the app can open SHALL open at a size declared for that kind, rather than all sub-windows filling the screen's visible area.

#### Scenario: Lookup popover opens at popover size
- **WHEN** a lookup window is opened, whether by hotkey, by service, or by deep link
- **THEN** it appears at the declared popover size (420 × 520 by default), not filling the screen.

#### Scenario: Document and tool windows open at their own declared sizes
- **WHEN** a notebook, single-note, ops tool, or password vault window is opened
- **THEN** it appears at the size declared for that window kind, and the previously uniform full-visible-frame sizing no longer applies.
- **AND** the transparent titlebar and full-size content view styling they had before are unchanged.

#### Scenario: A window kind that declares no size gets a sane default, not the screen
- **WHEN** a sub-window is opened that does not declare a size of its own
- **THEN** it opens at a moderate default size rather than filling the screen, and the transparent-titlebar styling applied before this capability is preserved.

#### Scenario: Window chrome styling is unchanged
- **WHEN** a sub-window is created with a declared size
- **THEN** the transparent titlebar, full-size content view, and other visual styling applied before this capability are preserved.

### Requirement: AI analysis is rendered as formatted Markdown
Wherever the app presents AI-generated analysis in a surface that already renders Markdown elsewhere, it SHALL use that same rendering rather than displaying the raw Markdown source as plain text.

#### Scenario: Lookup window renders AI analysis formatted
- **WHEN** the lookup window displays an AI deep-analysis result containing Markdown constructs such as lists, emphasis, headings, or code spans
- **THEN** those constructs are rendered visually, and no literal Markdown syntax characters are shown as plain text.

#### Scenario: Plain-text lookups are unaffected
- **WHEN** the AI result contains no Markdown constructs
- **THEN** it renders as continuous prose, identical to how it appeared before this requirement.

### Requirement: Deep-link lookup popover does not activate the host application
Opening a lookup popover in response to a browser deep link SHALL NOT bring the desktop application — and with it the main window — to the foreground. The popover is a lightweight bubble over whatever the user is reading, not an application switch.

#### Scenario: Deep link from the browser does not surface the main window
- **WHEN** the user triggers "问 AI 深度解析" or "在桌面端打开" in the browser companion while the desktop app is in the background
- **THEN** the lookup popover appears, and the desktop app's main window is not brought forward or activated.

#### Scenario: The popover remains usable without activating the app
- **WHEN** the popover is shown this way
- **THEN** it is visible and interactive over the browser, and the browser does not lose foreground status.

#### Scenario: Popover still appears even though the app is not activated
- **WHEN** the popover is created without activating the application
- **THEN** the popover is still shown — suppressing the activation does not suppress the window.

#### Scenario: Other entry points behave the same way
- **WHEN** the lookup popover is opened by hotkey, by macOS service, or by the extension's right-click fallback
- **THEN** it likewise does not activate the desktop application, since all entry points share one launcher.

#### Scenario: Other sub-windows are unaffected
- **WHEN** the user opens a notebook, single-note, ops tool, or password vault window
- **THEN** that window activates the application as before — for those, activation is the expected result of an explicit open request. This requirement is scoped to the lookup popover.

