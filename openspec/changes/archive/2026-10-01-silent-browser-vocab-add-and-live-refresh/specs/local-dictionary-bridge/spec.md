## ADDED Requirements

### Requirement: Loopback vocabulary mutation endpoint
The desktop application SHALL expose an HTTP endpoint on the IPv4 loopback bridge allowing authenticated local clients to insert vocabulary words directly into the vocabulary store without activating the desktop application or surfacing its main window.

#### Scenario: Add word via vocabulary bridge endpoint
- **WHEN** an authenticated client sends a request to add a word to the vocabulary endpoint and the word does not yet exist
- **THEN** the entry is inserted into the vocabulary store, a change notification is broadcast, and the bridge responds with success status indicating the entry was added.

#### Scenario: Word already exists in vocabulary
- **WHEN** an authenticated client requests to add a word that is already present in the vocabulary store
- **THEN** the bridge does not insert duplicate entries and responds with a distinct success status indicating the word is already present.

#### Scenario: Unauthorized vocabulary request rejected
- **WHEN** a client sends a request to the vocabulary endpoint with a missing or invalid bridge secret
- **THEN** the bridge rejects the request with an unauthorized status code and does not modify the vocabulary store.
