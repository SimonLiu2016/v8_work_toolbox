# ai-configuration Delta

## ADDED Requirements

### Requirement: Provider credential masking with explicit reveal
The provider API key field SHALL be masked by default and SHALL provide an explicit reveal affordance so the user can confirm the credential currently in effect. The raw credential MUST NOT be rendered on screen without an explicit user action. Revealing a stored credential SHALL be read-only with respect to the secure store.

#### Scenario: Credential field masked by default
- **WHEN** the provider dialog opens
- **THEN** the API key field displays masked (asterisk) content by default
- **AND** the raw credential is not rendered on screen without an explicit user action.

#### Scenario: Reveal the credential being entered
- **WHEN** user types a credential into the field and activates the reveal affordance
- **THEN** the field switches from masked to plain display so the user can verify what was entered
- **AND** activating the affordance again returns it to masked display.

#### Scenario: Reveal the already-stored credential when editing
- **WHEN** user edits an existing provider, whose key field is empty, and activates the reveal affordance
- **THEN** the system loads the currently stored credential from the secure store and displays it for inspection
- **AND** it indicates that the stored credential was loaded rather than typed by the user.

#### Scenario: Revealing a stored credential does not rewrite it
- **WHEN** user reveals the stored credential and then saves the provider without modifying the field
- **THEN** the stored credential is left unchanged, with no redundant write to the secure store.

#### Scenario: Stored credential unavailable
- **WHEN** user activates the reveal affordance but the credential cannot be read from the secure store
- **THEN** the system reports that the credential could not be loaded, rather than silently showing an empty field.
