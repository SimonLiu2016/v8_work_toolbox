## MODIFIED Requirements

### Requirement: Service worker delegated dictionary lookups
The browser companion SHALL execute dictionary queries through the desktop application's local dictionary bridge (`local-dictionary-bridge`) instead of calling external dictionary APIs directly, and SHALL declare host permission for the bridge's loopback address in `manifest.json`. Every outbound dictionary request from the service worker SHALL carry an explicit client-side timeout.

#### Scenario: In-page word lookup bypassing webpage CSP and CORS
- **WHEN** user selects an English word on any webpage (e.g. Baidu Baike, GitHub, Medium) and clicks the V8 floating action icon
- **THEN** the content script sends a message to the background service worker, which queries the local bridge with the shared secret; the bridge returns definitions, phonetics, and audio URLs to the in-page bubble within 800ms, unaffected by the host page's CSP or by the dictionary server's own origin policy.

#### Scenario: Query fallback on dictionary failure
- **WHEN** the local dictionary bridge cannot find the word in primary dictionary resolution
- **THEN** the bubble displays an informative state with an option to open the desktop V8 Work Toolbox for AI deep analysis.

## ADDED Requirements

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

## REMOVED Requirements

### Requirement: Direct external dictionary API queries from the service worker
**Reason**: Measured behavior shows external dictionary endpoints reject extension-origin requests outright — `dict.youdao.com/jsonapi` returns `403 Invalid CORS request` and `api.dictionaryapi.dev` returns a Cloudflare `522` after roughly 20 seconds. `host_permissions` suppresses only the browser-side CORS check and does not remove the `Origin` request header, so no extension-side change can make these endpoints succeed.
**Migration**: Dictionary resolution moves to the `local-dictionary-bridge` capability. The service worker queries the bridge instead of the external endpoints; the desktop application performs the outbound dictionary request without an extension `Origin` header. The external dictionary host permissions are removed from `manifest.json`.
