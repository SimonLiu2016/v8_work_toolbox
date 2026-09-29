## ADDED Requirements

### Requirement: Global theme mode persistence and reactive notification
The unified settings store SHALL persist the user's selected theme mode (`system`, `light`, `dark`) in `app.json` and expose a reactive `ValueNotifier<ThemeMode>` so all listening widgets can update immediately upon configuration changes.

#### Scenario: Persisting theme preference
- **WHEN** user chooses a theme mode in the settings interface
- **THEN** the preference is written to `app.json` under the key `themeMode`, defaulting to `system` if not configured.

#### Scenario: Reactive update notification
- **WHEN** the theme mode setting is updated
- **THEN** the `themeModeNotifier` emits the new `ThemeMode` value and any open windows listening to the notifier rebuild their MaterialApp tree.
