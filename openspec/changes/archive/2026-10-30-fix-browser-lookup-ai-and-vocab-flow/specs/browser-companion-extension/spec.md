## MODIFIED Requirements

### Requirement: Unpacked extension reload after code change
Because the browser caches the service worker registered at install time, changing the extension's code on disk SHALL require an explicit reload of the unpacked extension before the new code takes effect.

#### Scenario: Extension reload required after extension code change
- **WHEN** the extension's own code changes on disk
- **THEN** the deployment instructions SHALL require reloading the unpacked extension so the browser stops running the previously registered service worker version.

## ADDED Requirements

### Requirement: Browser bubble actions express their intent through the deep link
The in-page bubble's action buttons SHALL each dispatch a deep link that names their actual intent, so that the desktop app performs the action the button promised rather than a generic lookup.

#### Scenario: Ask AI dispatches AI mode
- **WHEN** the user clicks the bubble's "问 AI 深度解析" action while the clipboard word was not found in the dictionary
- **THEN** the extension dispatches a lookup deep link carrying AI mode, so the desktop app goes directly to AI analysis instead of repeating the failed dictionary lookup.

#### Scenario: Add to vocabulary book dispatches the vocabulary action
- **WHEN** the user clicks the bubble's "加入词本" action
- **THEN** the extension dispatches a vocabulary deep link that adds the word without opening any window, and the bubble confirms the addition rather than announcing a window opening.

#### Scenario: Open on desktop keeps dictionary-first behaviour
- **WHEN** the user clicks the bubble's "在桌面端打开" action
- **THEN** the extension dispatches a lookup deep link with no mode parameter, preserving dictionary-first behaviour.

#### Scenario: Button labels match the dispatched action
- **WHEN** any bubble action is dispatched
- **THEN** the button's own confirmation text names the action actually taken — an action that adds a word confirms the addition, and does not display text about opening a window.
