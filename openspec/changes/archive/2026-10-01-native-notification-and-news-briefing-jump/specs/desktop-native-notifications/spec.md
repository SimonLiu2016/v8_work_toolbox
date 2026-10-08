## Purpose

Provides a unified macOS native desktop notification system across application services with action payloads and notification click/activation event dispatching.

## ADDED Requirements

### Requirement: Native desktop notification dispatch
The application SHALL deliver desktop notifications natively through the host platform's notification center (`NSUserNotificationCenter`), displaying the application's own icon and branding, and SHALL NOT delegate notification delivery to external command-line scripting utilities such as `osascript`.

#### Scenario: Dispatching a native notification
- **WHEN** any internal service (news scheduler, asset reminder, ops monitor) dispatches a notification
- **THEN** a native notification banner is displayed with the application's icon, title, subtitle, and informative body text, attributed to V8 Work Toolbox.

### Requirement: Notification click activation and routing
When a user activates a notification (clicks the notification banner or clicks the "Show" / action button), the system SHALL bring the application to the foreground and dispatch the notification action payload to the application shell for contextual navigation.

#### Scenario: User clicks notification banner
- **WHEN** user clicks a native notification delivered by the application
- **THEN** the application's main window is brought to the foreground and unminimized, and the notification's action type and payload are forwarded to the user interface for deep routing.
