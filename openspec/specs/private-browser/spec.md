# private-browser Specification

## Purpose
WKWebView-based private browser embedded in the privacy space, with multi-tab support, bookmarks, cross-session tab persistence, N-grid quick-launch homepage, and network proxy integration.

## Requirements

### Requirement: N-grid quick-launch homepage
The browser homepage SHALL display a user-configurable grid of site shortcuts, each with a title, URL, and auto-fetched favicon. Clicking a shortcut opens the URL in the current tab or a new tab. The user can add, remove, and reorder shortcuts.

#### Scenario: Open shortcut in current tab
- **WHEN** the user clicks a shortcut tile on the homepage
- **THEN** the browser navigates the current active tab to the shortcut URL

#### Scenario: Open shortcut in new tab
- **WHEN** the user long-presses or right-clicks a shortcut tile and selects "Open in New Tab"
- **THEN** the browser opens a new tab and navigates it to the shortcut URL, making the new tab active

#### Scenario: Add new shortcut
- **WHEN** the user clicks the "Add Shortcut" tile, enters a title and URL, and confirms
- **THEN** a new shortcut tile appears in the grid with the provided title and an auto-fetched favicon; if favicon fetch fails, a placeholder icon is used

#### Scenario: Remove shortcut
- **WHEN** the user right-clicks (or long-presses) an existing shortcut tile and selects "Remove"
- **THEN** the shortcut is permanently removed from the grid and the layout reflows

#### Scenario: Reorder shortcuts
- **WHEN** the user drags a shortcut tile to a new position in the grid
- **THEN** the grid updates the display order immediately and persists the new order to private storage

### Requirement: Multi-tab browsing with session persistence
The browser SHALL support opening multiple simultaneous tabs, switching between them, and closing them. All open tabs (URL, title, scroll position) SHALL persist across app sessions, stored in the private encrypted database.

#### Scenario: Open new tab
- **WHEN** the user clicks the "+" button in the tab bar or uses the keyboard shortcut
- **THEN** a new tab opens showing the quick-launch homepage, becomes the active tab, and a new tab entry appears in the tab bar

#### Scenario: Switch between tabs
- **WHEN** the user clicks a tab entry in the tab bar
- **THEN** the browser switches the main WKWebView to display that tab's content and updates the address bar to reflect the tab's current URL

#### Scenario: Close a tab
- **WHEN** the user clicks the close (×) button on a tab entry
- **THEN** that tab is removed from the tab bar; if it was the active tab, the browser activates the nearest remaining tab; if it was the last tab, the browser opens a new blank tab showing the homepage

#### Scenario: Tabs restored after app relaunch
- **WHEN** the user relaunches the app and authenticates into the privacy space
- **THEN** all previously open tabs are restored with their last visited URL and title, and the previously active tab is selected

### Requirement: Address bar navigation
The browser SHALL provide an address bar accepting full URLs and search queries. Navigation controls (back, forward, reload, stop) SHALL update according to the current page's navigation state.

#### Scenario: Navigate to URL
- **WHEN** the user types a valid URL into the address bar and presses Enter
- **THEN** the active tab loads the specified URL and the address bar displays the final resolved URL after any redirects

#### Scenario: Navigate via search query
- **WHEN** the user types a non-URL string into the address bar and presses Enter
- **THEN** the browser submits the query to the configured default search engine (e.g. Google) and loads the results page

#### Scenario: Back and forward navigation
- **WHEN** the user clicks the Back button while the tab has a previous navigation history entry
- **THEN** the tab navigates to the previous page; the Forward button becomes enabled

#### Scenario: Reload page
- **WHEN** the user clicks the Reload button or presses Cmd+R
- **THEN** the current page is reloaded from the network; the Stop button is shown during loading and reverts to Reload upon completion

### Requirement: Bookmarks management
The browser SHALL allow users to bookmark the current page (capturing title, URL, and favicon), view a bookmark list, remove bookmarks, and click a bookmark to open it.

#### Scenario: Bookmark current page
- **WHEN** the user clicks the Bookmark icon in the browser toolbar while on a loaded page
- **THEN** the current page is saved as a bookmark with its title, URL, and favicon; the bookmark icon changes to a filled/highlighted state to indicate the page is bookmarked

#### Scenario: View bookmark list
- **WHEN** the user opens the Bookmarks panel from the browser toolbar
- **THEN** a sidebar or sheet appears listing all saved bookmarks with their title, favicon, and URL

#### Scenario: Open bookmark
- **WHEN** the user clicks a bookmark entry in the bookmark list
- **THEN** the active tab navigates to the bookmarked URL and the bookmark panel closes

#### Scenario: Remove bookmark
- **WHEN** the user right-clicks a bookmark entry and selects "Remove Bookmark", or clicks Remove on the bookmark detail row
- **THEN** the bookmark is deleted from private storage and removed from the list immediately

#### Scenario: Detect already-bookmarked page
- **WHEN** the browser finishes loading a page whose URL already exists in the bookmark list
- **THEN** the bookmark icon in the toolbar appears filled/highlighted to signal the page is already saved

### Requirement: Network proxy integration
The browser's WKWebView SHALL inherit and apply network proxy settings from the global proxy manager. When a proxy is active, all browser traffic (HTTP and HTTPS) SHALL route through that proxy. Proxy changes take effect without requiring a browser restart.

#### Scenario: Browse through active proxy
- **WHEN** the global proxy is enabled and the user navigates to any URL in the private browser
- **THEN** all HTTP/HTTPS requests from the WKWebView are routed through the configured proxy host and port

#### Scenario: Proxy toggled off mid-session
- **WHEN** the user disables the global proxy while the private browser is open
- **THEN** subsequent navigations in the browser use a direct connection; the WKWebView configuration is refreshed to reflect the new proxy-free state

#### Scenario: Proxy requires authentication
- **WHEN** the configured proxy requires a username and password and the browser issues a request
- **THEN** the browser responds to the URLAuthenticationChallenge with the credentials stored in the proxy manager, transparently authenticating without prompting the user

### Requirement: Privacy isolation
The browser SHALL NOT store browsing history. All tabs and bookmarks SHALL be stored in the privacy space's private encrypted storage. No browser data SHALL be accessible outside the privacy space unlock session.

#### Scenario: No history recorded
- **WHEN** the user navigates across multiple pages within a session
- **THEN** no browsing history is written to disk or any general app database; only the currently open tab URLs are persisted as session state

#### Scenario: Bookmarks inaccessible before unlock
- **WHEN** the privacy space is locked
- **THEN** the bookmark list and tab session data are encrypted and cannot be read by any component outside the authenticated privacy space session

#### Scenario: Tabs cleared on explicit lock
- **WHEN** the user manually locks the privacy space
- **THEN** in-memory tab state is wiped and the WKWebView process pool is cleared, preventing residual page content from appearing until the next authenticated session restores tabs from encrypted storage
