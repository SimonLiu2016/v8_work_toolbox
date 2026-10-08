# local-dictionary-bridge Specification

## Purpose
Lets local trusted clients (the browser companion extension) resolve dictionary lookups through the desktop application, so dictionary logic lives in exactly one place and is immune to third-party CORS policy.
## Requirements
### Requirement: Loopback dictionary endpoint
The desktop application SHALL expose a single HTTP endpoint on the IPv4 loopback interface that resolves a word or short phrase into phonetic transcription, definitions, and an audio URL, reusing the desktop application's own dictionary resolution.

#### Scenario: Extension queries a word through the bridge
- **WHEN** a local client requests the endpoint with a word and the desktop application is running
- **THEN** the endpoint returns structured dictionary data (word, phonetic, definitions, audio URL) equivalent to what the desktop application's own lookup panel would render for the same word.

#### Scenario: Endpoint binds loopback only
- **WHEN** the desktop application starts the bridge
- **THEN** the endpoint listens on the IPv4 loopback address only and is not reachable from other network interfaces.

#### Scenario: Word absent from dictionary
- **WHEN** a local client requests a term that dictionary resolution cannot match
- **THEN** the endpoint responds with a distinguishable "no match" result containing the requested term and an empty definition set, rather than a transport error.

### Requirement: Bridge access authentication
The bridge SHALL require a shared secret on every request and SHALL reject requests that do not carry it.

#### Scenario: Request without secret
- **WHEN** a request arrives without the shared secret
- **THEN** the endpoint responds with an authorization failure and performs no dictionary lookup.

#### Scenario: Request with wrong secret
- **WHEN** a request arrives with a secret that does not match the one the desktop application issued
- **THEN** the endpoint responds with an authorization failure and performs no dictionary lookup.

#### Scenario: Secret persists across desktop application restarts
- **WHEN** the desktop application restarts after a client has received the secret once
- **THEN** the same secret remains valid, so the client does not need to be reconfigured.

### Requirement: Bridge lifecycle bound to host application
The bridge SHALL be available whenever the desktop application's main window is running and SHALL stop listening when the application shuts down.

#### Scenario: Bridge not running when desktop application is closed
- **WHEN** the desktop application is not running and a local client attempts to reach the endpoint
- **THEN** the connection is refused, and the client reports the bridge as offline rather than reporting a dictionary failure.

#### Scenario: Bridge stops on application shutdown
- **WHEN** the desktop application exits (window close or termination signal)
- **THEN** the bridge stops listening so no orphan process holds the port.

### Requirement: Bridge failure does not disrupt the host application
A failure in the bridge (port already occupied, malformed request, unexpected exception) SHALL NOT prevent the desktop application from starting or crash the running application.

#### Scenario: Port already in use
- **WHEN** the desktop application starts and the bridge's port is occupied by another process
- **THEN** the desktop application continues to start normally, records a diagnostic signal that the bridge did not start, and all other lookup paths remain functional.

#### Scenario: Malformed request
- **WHEN** a client sends a request the endpoint cannot parse
- **THEN** the endpoint responds with a client error and remains available for subsequent requests.

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

