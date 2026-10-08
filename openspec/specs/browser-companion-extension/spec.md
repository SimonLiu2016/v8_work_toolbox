# browser-companion-extension Specification

## Purpose
Provides a secure, lightweight browser companion extension for Google Chrome and Chromium browsers that offers in-page word lookup bubbles, dictionary queries delegated to the desktop application's local bridge, and one-click note capturing into V8 Work Toolbox.
## Requirements
### Requirement: Service worker delegated dictionary lookups
The browser companion SHALL execute dictionary queries through the desktop application's local dictionary bridge (`local-dictionary-bridge`) instead of calling external dictionary APIs directly, and SHALL declare host permission for the bridge's loopback address in `manifest.json`. Every outbound dictionary request from the service worker SHALL carry an explicit client-side timeout.

#### Scenario: In-page word lookup bypassing webpage CSP and CORS
- **WHEN** user selects an English word on any webpage (e.g. Baidu Baike, GitHub, Medium) and clicks the V8 floating action icon
- **THEN** the content script sends a message to the background service worker, which queries the local bridge with the shared secret; the bridge returns definitions, phonetics, and audio URLs to the in-page bubble within 800ms, unaffected by the host page's CSP or by the dictionary server's own origin policy.

#### Scenario: Query fallback on dictionary failure
- **WHEN** the local dictionary bridge cannot find the word in primary dictionary resolution
- **THEN** the bubble displays an informative state with an option to open the desktop V8 Work Toolbox for AI deep analysis.

### Requirement: Bridge resolution succeeds where external APIs fail
The browser companion SHALL obtain dictionary results that are equivalent to the desktop application's own lookups, regardless of whether the upstream dictionary server accepts extension-origin requests.

#### Scenario: Word whose external endpoint rejects extension origins
- **WHEN** the word is one whose external dictionary endpoint rejects extension-origin requests with a CORS failure
- **THEN** the bridge still returns desktop-quality results, because the desktop application issues its own dictionary request without an extension `Origin` header.

### Requirement: Bounded service worker dictionary requests
Every dictionary request the service worker makes SHALL be bounded by an explicit client-side timeout, and a timeout or transport failure SHALL be reported to the bubble rather than left pending.

#### Scenario: Service worker request timeout
- **WHEN** the bridge does not respond within the service worker's request timeout
- **THEN** the service worker aborts the request and reports failure to the bubble, so the bubble is never left in a permanent loading state.

#### Scenario: Desktop application not running
- **WHEN** the user triggers a lookup while the desktop application is closed and the bridge port refuses the connection
- **THEN** the bubble reports the bridge as offline and offers to open the desktop application, and the service worker SHALL NOT spend longer than the bridge timeout before reporting this.

### Requirement: Distinguishable lookup failure states
The browser companion SHALL present bridge authorization failure, transport failure, and a genuine "no match" result as distinguishable bubble states.

#### Scenario: Three failure kinds rendered differently
- **WHEN** the bridge reports an authorization failure, a transport failure, or an empty definition set for the term
- **THEN** the bubble renders each with its own message and recovery action rather than presenting all of them as a lookup failure.

### Requirement: Unpacked extension reload after code change
Because the browser caches the service worker registered at install time, changing the extension's code on disk SHALL require an explicit reload of the unpacked extension before the new code takes effect.

#### Scenario: Extension reload required after extension code change
- **WHEN** the extension's own code changes on disk
- **THEN** the deployment instructions SHALL require reloading the unpacked extension so the browser stops running the previously registered service worker version.

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

