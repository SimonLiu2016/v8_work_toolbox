## ADDED Requirements

### Requirement: Silent vocabulary insertion from in-page bubble
The browser companion SHALL route in-page bubble "加生词本" actions through the background service worker to the local dictionary bridge via HTTP, avoiding OS-level URL scheme activation (`v8toolbox://`) that would bring the desktop application to the foreground.

#### Scenario: User clicks add to vocabulary in browser bubble
- **WHEN** user clicks "加生词本" in the in-page word lookup card while the desktop application is running
- **THEN** the request is sent quietly via the local bridge, the button label updates to "已加入生词本 ✓" in-place, the desktop application's main window is NOT activated or brought to the foreground, and the card dismisses smoothly after a brief delay.

#### Scenario: Word already exists when added in browser bubble
- **WHEN** user clicks "加生词本" for a term already in the vocabulary book
- **THEN** the bridge reports the word is already present, the button label reflects "已在生词本" in-place, and no duplicate entry is created.

#### Scenario: Bridge offline when adding to vocabulary
- **WHEN** user clicks "加生词本" but the local bridge is unreachable (desktop application closed or bridge uninitialized)
- **THEN** the bubble displays a graceful failure notification indicating the desktop application is not running, without navigating to an OS URL scheme.
